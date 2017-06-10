import PathKit
import Async
import SwiftyBeaver
import Cron
import JSON

enum ConversionError: Error {
    case maxThreadsReached
    case noJobsLeft
    case noJobIndex
}

class ConversionQueue: JSONConvertible {
    static let filename: String = "conversionqueue.json"

    fileprivate var configPath: Path
    fileprivate var statistics: Statistic
    fileprivate var maxThreads: Int
    fileprivate var deleteOriginal: Bool
    fileprivate var log: SwiftyBeaver.Type
    fileprivate var videoConversionConfig: VideoConversionConfig
    fileprivate var audioConversionConfig: AudioConversionConfig

    fileprivate var jobs: [ConvertibleMedia] = []
    fileprivate var activeJobs: [ConvertibleMedia] = []

    var conversionGroup: AsyncGroup = AsyncGroup()
    var stop: Bool = false

    var active: Int {
        return activeJobs.count
    }
    var waiting: Int {
        return jobs.count
    }

    init(_ config: Config, statistics stats: Statistic? = nil) {
        configPath = config.configFile
        maxThreads = config.convertThreads
        deleteOriginal = config.deleteOriginal
        if stats != nil {
            statistics = stats!
        } else {
            statistics = Statistic()
        }
        log = config.log
        videoConversionConfig = VideoConversionConfig(container: config.convertVideoContainer, videoCodec: config.convertVideoCodec, audioCodec: config.convertAudioCodec, subtitleScan: config.convertVideoSubtitleScan, mainLanguage: config.convertLanguage, maxFramerate: config.convertVideoMaxFramerate, plexDir: config.plexDirectory, tempDir: config.deleteOriginal ? nil : config.convertTempDirectory)
        audioConversionConfig = AudioConversionConfig(container: config.convertAudioContainer, codec: config.convertAudioCodec, plexDir: config.plexDirectory, tempDir: config.deleteOriginal ? nil : config.convertTempDirectory)
    }

    /// Adds a new Media object to the list of media items to convert
    func push(_ job: inout ConvertibleMedia) {
        if !jobs.contains(where: { $0.path == job.path }) {
            jobs.append(job)
        }
    }

    @discardableResult
    fileprivate func pop() -> ConvertibleMedia? {
        self.activeJobs.append(self.jobs.removeFirst())
        return self.activeJobs.last
    }

    fileprivate func finish(_ job: ConvertibleMedia) throws {
        guard let index = self.activeJobs.index(where: { $0.path == job.path }) else {
            throw ConversionError.noJobIndex
        }
        self.activeJobs.remove(at: index)
    }

    fileprivate func requeue(_ job: ConvertibleMedia) {
        let index = self.activeJobs.index(where: { $0.path == job.path })!
        self.jobs.append(self.activeJobs.remove(at: index))
    }

    func startNextConversion() throws {
        guard self.active < self.maxThreads else {
            throw ConversionError.maxThreadsReached
        }
        guard var next = self.pop() else {
            throw ConversionError.noJobsLeft
        }
        conversionGroup.utility {
            self.statistics.measure(.convert) {
                do {
                    if next is Video {
                        next = try next.convert(self.videoConversionConfig, self.log)
                    } else if next is Audio {
                        next = try next.convert(self.audioConversionConfig, self.log)
                    } else {
                        // We shouldn't be able to convert anything else, and we
                        // shouldn't have even put anything else in the queue.
                        // Calling convert on a BaseMedia object should throw an
                        // Unimplemented Error
                        next = try next.convert(nil, self.log)
                    }
                    try self.finish(next)
                } catch MediaError.notImplemented {
                    self.log.warning("Media that is neither Video nor Audio somehow ended up in the conversion queue! => \(next.path)")
                } catch ConversionError.noJobIndex {
                    self.log.error("Error finding job index in the active jobs array. Unable to remove job, this will prevent other jobs from starting!")
                } catch {
                    self.log.warning("Error while converting media: \(next.path)")
                    self.log.error(error)
                    self.requeue(next)
                }
            }
        }
    }

    func start() {
        self.log.info("Beginning conversion cron job")
        while !stop {
            do {
                try self.startNextConversion()
            } catch ConversionError.maxThreadsReached {
                self.log.info("Reached the concurrent conversion thread limit. Waiting for a thread to be freed")
            } catch ConversionError.noJobsLeft {
                self.log.info("All conversion jobs are either finished or currently running")
                break
            } catch {
                self.log.error("Uncaught expection occurred while converting media => '\(error)'")
            }
            while active == maxThreads && !stop {
                conversionGroup.wait(seconds: 60)
            }
        }
        self.log.info("Conversion cron job will stop as soon as the current conversion jobs have finished")
        conversionGroup.wait()
        self.log.info("The conversion cron job is officially done running (for now)")
    }

    convenience init(_ path: Path) throws {
        try self.init(path.read())
    }

    convenience init(_ str: String) throws {
        try self.init(json: JSON.Parser.parse(str))
    }

    required init(json: JSON) throws {
        configPath = Path(try json.get("configPath"))
        config = try Config(configPath.read())
        maxThreads = config.convertThreads
        deleteOriginal = config.deleteOriginal
        statistics = Statistic()
        log = config.log
        videoConversionConfig = VideoConversionConfig(container: config.convertVideoContainer, videoCodec: config.convertVideoCodec, audioCodec: config.convertAudioCodec, subtitleScan: config.convertVideoSubtitleScan, mainLanguage: config.convertLanguage, maxFramerate: config.convertVideoMaxFramerate, plexDir: config.plexDirectory, tempDir: config.deleteOriginal ? nil : config.convertTempDirectory)
        audioConversionConfig = AudioConversionConfig(container: config.convertAudioContainer, codec: config.convertAudioCodec, plexDir: config.plexDirectory, tempDir: config.deleteOriginal ? nil : config.convertTempDirectory)
        jobs = ConversionQueue.setupJobs(try json.get("jobs"))
    }

    private static func setupJobs(_ jobs: [BaseConvertibleMedia]) -> [ConvertibleMedia] {
        return jobs
    }

    public func encoded() -> JSON {
        var js: [BaseConvertibleMedia] = []
        for j in jobs {
            if j is Video {
                js.append(j as! Video)
            } else if j is Audio {
                js.append(j as! Audio)
            } else {
                js.append(j as! BaseConvertibleMedia)
            }
        }
        return [
            "configPath": configPath.string,
            "jobs": js.encoded()
        ]
    }

    private func serialized() throws -> String {
        return try self.encoded().serialized()
    }

    public func save() throws {
        let file: Path = configPath.parent + ConversionQueue.filename
        try file.write(self.serialized(), force: true)
    }
}
