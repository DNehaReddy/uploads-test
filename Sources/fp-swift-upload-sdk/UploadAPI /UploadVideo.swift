
import Foundation
import Network
import UIKit

// A class for uploading videos in chunks with progress tracking and network monitoring.
public class Uploader {
    
    var chunksData = ChunkModel2(chunksUrlList: [], chunksData: [])
    var objectName: String?
    var uploadId: String?
    var uploadUrls: [String] = []
    var chunkAttempt: Int = 0
    public var progressHandler: ((Float) -> Void)?
    typealias CompletionHandler = (Bool) -> Void
    var dataTasks: [URLSessionDataTask] = []
    var isPaused: Bool = false
    var monitor :  NWPathMonitor?
    public let queue = DispatchQueue.global()
    
    
    // MARK: - Initialization
    ///Creates a new default instance of `UploadVideo`.
    public init() {
        monitor  = NWPathMonitor()
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
        
    /// Calculates the number of chunks required to upload a video based on file size and chunk size.
    ///
    /// - Parameters:
    ///   - file: The URL of the video file to be uploaded.
    ///   - chunkSize: The desired size of each video chunk in bytes.
    ///   - completion: A closure to be called with the calculated number of chunks (if successful) or an error.
    public  func calculateNumberOfChunks(for file: URL, chunkSize: Int, completion: @escaping (Int?, Error?) -> Void) {
        do {
            // Get file size
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            guard let fileSize = attributes[.size] as? UInt64 else {
                completion(nil, NSError(domain: "FileManagerError", code: 100, userInfo: [NSLocalizedDescriptionKey: "Failed to retrieve file size."]))
                return
            }
            let totalChunks = numberOfChunks(for: fileSize, chunkSize: chunkSize)
            completion(totalChunks, nil)
            
        } catch {
            completion(nil, error)
        }
    }
    
    /// Calculates the total number of chunks required to upload a video based on file size and chunk size.
    ///
    /// - Parameters:
    ///   - fileSize: The size of the video file in bytes.
    ///   - chunkSize: The desired size of each video chunk in bytes.
    /// - Returns: The total number of chunks required for upload.
    func numberOfChunks(for fileSize: UInt64, chunkSize: Int) -> Int {
        let fullChunks = Int(fileSize) / chunkSize
        let hasPartialChunk = (fileSize % UInt64(chunkSize)) != 0
        return fullChunks + (hasPartialChunk ? 1 : 0)
    }
    
    
    /// Splits a video file into chunks of a specified size and saves them temporarily.
    ///
    /// - Parameters:
    ///   - url: The URL of the video file to be split.
    ///   - chunkSize: The desired size of each video chunk in bytes.
    ///   - completion: A closure to be called with success/failure status, total number of chunks, and any errors encountered.
    public func splitVideoFile(at url: URL, withChunkSize chunkSize: Int, completion: @escaping (Bool,Int,Error?) -> Void) {
        calculateNumberOfChunks(for: url, chunkSize: chunkSize) { [weak self] totalChunks, error in
            guard let totalChunks = totalChunks else {
                completion(false, totalChunks ?? 0, error)
                return
            }
            
            do {
                // Open the file for reading
                let fileHandle = try FileHandle(forReadingFrom: url)
                defer {
                    fileHandle.closeFile()
                }
                
                var fileOffset: UInt64 = 0
                let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! UInt64
                var chunkIndex = 0
                var chunksData: [Data] = []
                var chunksUrls: [String] = []
                let fiveMBInBytes: Int64 = 5 * 1024 * 1024
                if chunkSize < fiveMBInBytes {
                    print("The file size is less than 5MB.....")
                    completion(false,0,NSError(domain: "ChunkError", code: 0, userInfo: [NSLocalizedDescriptionKey: "File size should be more than 5 MB"]))
                }
                
                while fileOffset < fileSize {
                    // Calculate the remaining file size
                    let remainingFileSize = fileSize - fileOffset
                    let currentChunkSize = min(chunkSize, Int(remainingFileSize))
                    
                    // Read a chunk
                    fileHandle.seek(toFileOffset: fileOffset)
                    let data = fileHandle.readData(ofLength: currentChunkSize)
                    let chunkPath = FileManager.default.temporaryDirectory.appendingPathComponent("chunk_\(chunkIndex).data")
                    do {
                        try data.write(to: chunkPath)
                        chunksData.append(data)
                        chunksUrls.append(chunkPath.path)
                        print("Chunk \(chunkIndex) saved at \(chunkPath)")
                    } catch {
                        completion(false,0,NSError(domain: "ChunkError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to save chunk \(chunkIndex): \(error)"]))
                        print("Failed to save chunk \(chunkIndex): \(error)")
                        return
                    }
                    self?.saveChunk(data: data, index: chunkIndex)
                    // Update offset and index for next chunk
                    fileOffset += UInt64(currentChunkSize)
                    chunkIndex += 1
                }
                // All chunks processed successfully
                completion(true,totalChunks,nil)
            } catch {
                // Handle any errors
                print("Error: \(error)")
                completion(false,0, NSError(domain: "FileManagerError", code: 100, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]))
            }
        }
    }
    
    /// Saves a chunk of video data to the temporary directory.
    func saveChunk(data: Data, index: Int) {
        let  chunkPath = FileManager.default.temporaryDirectory.appendingPathComponent("chunk_\(index).data")
        do {
            try data.write(to: chunkPath)
            chunksData.chunksData.append(data)
            print("Chunk \(index) saved at \(chunkPath)")
        } catch {
            print("Failed to save chunk \(index): \(error)")
        }
        chunksData.chunksUrlList.append(chunkPath.path)
        print("chunks array : \(chunksData.chunksData)")
        print("Chunks list : \(chunksData.chunksUrlList)")
    }
    
    /// Initiates a multipart video upload process on the server.
    public func uploadVideoFile(endpoint: URL, noOfChunks: Int, completion: @escaping (Bool, Error?) -> Void) {
        guard let url = URL(string: "https://v1.fastpix.io/on-demand/uploads/multipart") else {
            print("Invalid URL")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        self.startMonitoringNetwork()
        let params = [
            "signedUrl": endpoint.absoluteString,
            "partitions": noOfChunks,
            "action": "init"
        ] as [String : Any]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: params) else {
            return
        }
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
                completion(false, NSError(domain: "Uploading error", code: 0, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]))
                return
            }
            if let httpResponse = response as? HTTPURLResponse {
                print("HTTP Status Code: \(httpResponse.statusCode)")
                print("HTTP RESPONSE : \(httpResponse)")
            }
            
            if let headers = request.allHTTPHeaderFields {
                print("Headers:")
                for (key, value) in headers {
                    print("\(key): \(value)")
                }
            } else {
                print("No headers found")
            }
            
            do {
                if let jsonObject = try JSONSerialization.jsonObject(with: data!, options: []) as? [String: Any] {
                    print("++++++++++++++", jsonObject)
                    let success = jsonObject["success"] as? Int
                    let dataDict = jsonObject["data"] as? [String: Any]
                    if success == 1 {
                        print("Success:", success)
                        
                        if let name = dataDict?["objectName"] as? String {
                            self?.objectName = name
                        }
                        if let uploadingId = dataDict?["uploadId"] as? String {
                            self?.uploadId = uploadingId
                            print("Upload ID:", self?.uploadId)
                        }
                        if let uploadingUrls = dataDict?["uploadUrls"] as? [String] {
                            self?.uploadUrls = uploadingUrls
                            print("Upload URLs:", self?.uploadUrls)
                        }
                        
                    } else {
                        let dataDict = jsonObject["error"] as? [String: Any]
                        let errorCode = dataDict?["code"] as? Int
                        let errorMessage = dataDict?["message"] as? String
                        completion(false, NSError(domain: "Uploading error", code: errorCode ?? 500, userInfo: [NSLocalizedDescriptionKey: "Error Code: \(errorCode) \(errorMessage)"]))
                    }
                } else {
                    completion(false, NSError(domain: "Uploading error", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unable to parse JSON as dictionary"]))
                    print("Error: Unable to parse JSON as dictionary")
                }
            } catch {
                completion(false, NSError(domain: "Uploading error", code: 0, userInfo: [NSLocalizedDescriptionKey: "Error decoding JSON:\(error.localizedDescription)"]))
                print("Error decoding JSON:", error)
            }
            self?.uploadChunksToServer(completion: { success, error in
                if let error = error {
                    completion(false, error)
                } else {
                    completion(true, nil)
                }
            })
        }
        task.resume()
    }

    
    /// Uploads individual video chunks to the server.
    func uploadChunksToServer(completion: @escaping (Bool, Error?) -> Void) {
        let chunksDataList = chunksData.chunksData
        let totalChunks = chunksDataList.count
        var uploadedChunks = 0
        var uploadError: Error?
        let maxRetries = 3

        func uploadNextChunk(index: Int) {
            guard index < chunksDataList.count else {
                // All chunks uploaded
                if let error = uploadError {
                    completion(false, error)
                } else {
                    self.sendCompleteUploadPostRequest { isUploaded, error in
                        if let error = error {
                            completion(false, error)
                        } else {
                            completion(true, nil)
                        }
                    }
                }
                return
            }

            let chunk = chunksDataList[index]
            let urlString = uploadUrls[index]
            guard let url = URL(string: urlString) else {
                completion(false, NSError(domain: "Uploading error", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
                print("Error: Invalid URL")
                return
            }

            uploadChunk(chunk, to: url, retries: maxRetries) { [weak self] success, error in
                if let error = error {
                    uploadError = error
                    print("Error: \(error)")
                    completion(false, error)
                    return
                } else if success {
                    uploadedChunks += 1
                    let progress = Float(uploadedChunks) / Float(totalChunks)
                    print("Upload progress: \(progress)")
                    self?.progressHandler?(progress)
                    // Upload next chunk
                    uploadNextChunk(index: index + 1)
                }
            }
        }

        // Start uploading from the first chunk
        uploadNextChunk(index: 0)
    }

    private func uploadChunk(_ chunk: Data, to url: URL, retries: Int, completion: @escaping (Bool, Error?) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = chunk
        print("Starting upload for chunk to URL: \(url)")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                if retries > 0 {
                    print("Retrying... (\(retries) attempts left)")
                    self.retryUploadChunk(chunk, to: url, retries: retries - 1, completion: completion)
                } else {
                    completion(false, NSError(domain: "Uploading error", code: 0, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]))
                }
            } else if let response = response as? HTTPURLResponse, response.statusCode == 200 {
                completion(true, nil)
            } else {
                completion(false, NSError(domain: "Uploading error", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to upload chunk"]))
            }
        }
        dataTasks.append(task)
        task.resume()
    }
    private func retryUploadChunk(_ chunk: Data, to url: URL, retries: Int, completion: @escaping (Bool, Error?) -> Void) {
        // Wait until uploads are resumed if they are paused
        DispatchQueue.global().async {
            while self.isPaused {
                print("Upload paused, waiting to retry...")
                Thread.sleep(forTimeInterval: 1) // Wait for 1 second before checking again
            }
            self.uploadChunk(chunk, to: url, retries: retries, completion: completion)
        }
    }
    
    // Function to send data chunks
    func sendDataChunks() {
        for dataTask in dataTasks {
            if !isPaused {
                print("Resuming task: \(dataTask)")
                dataTask.resume() // Start or resume each task if not paused
            }
        }
    }

    // Function to pause data tasks
    public func pause() {
        isPaused = true
        for dataTask in dataTasks {
            if dataTask.state == .running {
                print("Pausing task: \(dataTask)")
                dataTask.suspend() // Pause each task
            }
        }
    }

    // Function to resume data tasks
    public func resume() {
        isPaused = false
        for dataTask in dataTasks {
            if dataTask.state == .suspended {
                print("Resuming task: \(dataTask)")
                dataTask.resume() // Resume each task if not paused
            }
        }
    }

    // Function to start monitoring the network as soon as app becomes active
    @objc func appDidBecomeActive() {
        print("The app has become active again!!!")
        startMonitoringNetwork()
    }
    
    //start monitoring the network conditions
    public func startMonitoringNetwork() {
        if isPaused == true {
            monitor?.pathUpdateHandler = { [weak self] path in
                if path.status == .satisfied {
                    DispatchQueue.main.async {
                        self?.resume()
                        print("Video upload resumed!!!")
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.pause()
                        print("Video upload paused!!!")
                    }
                }
            }
        }
        let queue = DispatchQueue(label: "NetworkMonitor")
        monitor?.start(queue: queue)
    }
    
    //stop monitoring the network conditions
    func stopMonitoringNetwork() {
        monitor?.cancel()
    }
    
    ///Sends a final POST request to the server to signal completion of the multipart video upload.
    func sendCompleteUploadPostRequest(completion: @escaping (Bool?,Error?) -> Void) {
        guard let url = URL(string: "https://v1.fastpix.io/on-demand/uploads/multipart") else {
            print("Invalid URL")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let paramsRequestData = [
            "objectName": objectName,
            "uploadId": uploadId,
            "action": "complete"
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: paramsRequestData) else {
            return
        }
        
        request.httpBody = jsonData
        
        if let userAgent = request.allHTTPHeaderFields?["User-Agent"] {
            print("User-Agent: \(userAgent)")
        } else {
            print("User-Agent header not found")
        }
        
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let task = URLSession.shared.dataTask(with: request) { data , response, error in
            guard let httpResponse = response as? HTTPURLResponse else {
                return print("Http response not found")
            }
            print("HTTP Status Code for complete upload api: \(httpResponse.statusCode)")
            do {
                if let jsonObject = try JSONSerialization.jsonObject(with: data!, options: []) as? [String: Any] {
                    let success = jsonObject["success"] as? Int
                    if success == 1 {
                        completion(true, nil)
                    } else {
                        let dataDict = jsonObject["error"] as? [String: Any]
                        let errorCode = dataDict?["code"] as? Int
                        let errorMessage = dataDict?["message"] as? String
                        completion(false,  NSError(domain: "Uploading error", code: errorCode ?? 500 , userInfo: [NSLocalizedDescriptionKey: "Error Code: \(errorCode!) \(errorMessage!)"]))
                    }
                }
            } catch {
                
            }
            
            if let headers = request.allHTTPHeaderFields {
                print("Headers:")
                for (key, value) in headers {
                    print("\(key): \(value)")
                }
            } else {
                completion(false, error)
                print("No headers found")
            }
            
            if let error = error {
                completion(false,  NSError(domain: "Uploading error", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]))
                print("Error: \(error.localizedDescription)")
                return
            }
            
            if let data = data {
                self.stopMonitoringNetwork()
                completion(true, nil)
            }
        }
        task.resume()
    }
    
    // Deinitializes the observer
    deinit {
        stopMonitoringNetwork()
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        
    }
}

struct ChunkModel2 {
    var chunksUrlList: [String]
    var chunksData: [Data]
}
