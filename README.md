# NetworkingKit

A lightweight, modular, and powerful Swift networking library built using `async/await`, `Combine`, and `Alamofire`. Supports GET, POST, and multipart requests with built-in error handling.

---

## 🚀 Features

- ✅ Async/Await Support
- ✅ Combine Publisher Support
- ✅ Multipart Upload (Image, Video, PDF, etc.)
- ✅ Custom Error Handling
- ✅ Easy to extend
- ✅ Built with Swift 5 and Alamofire

---

## 📦 Installation

### Swift Package Manager (SPM)

Go to **Xcode > File > Add Packages** and add the following URL:
```swift
https://github.com/hummasyousuf/NetworkingKit
```
---

## 📲 Usage

### 1. Import the Package

```swift
import NetworkingKit
import Combine
```
### 2. SwiftUI Injection

```swift
@StateObject var viewModel: ContentViewModel
private var cancellable = Set<AnyCancellable>()

init() {
    let networking = Networking(baseURLString: "<your-baseurl>")
    _viewModel = StateObject(wrappedValue: ContentViewModel(networking: networking))
}
```
### 3. UIKit Injection

```swift
var viewModel: ContentViewModel
private var cancellable = Set<AnyCancellable>()

init() {
    let networking = Networking(baseURLString: "<your-baseurl>")
    viewModel = ContentViewModel(networking: networking)
    super.init(nibName: nil, bundle: nil)
}
```
### 4. GET & POST (Async/Await)
```swift
func getUsers() async {
    do {
        let model = try await networking.get(
            endPoint: "<your-endpoint>",
            headers: [:],
            query: [:],
            modelType: [YourModel].self
        )
        print("Model:", model)
    } catch {
        print("Error:", error.localizedDescription)
    }
}

func createPost() async {
    let params: [String: Any] = [
        "title": "Developer",
        "body": "iOS Developer",
        "userId": 1
    ]
    
    do {
        let model = try await networking.post(
            endPoint: "<your-endpoint>",
            headers: [:],
            params: params,
            modelType: YourModel.self
        )
        print("Model:", model)
    } catch {
        print("Error:", error.localizedDescription)
    }
}
```
### 5. GET & POST (Combine)
```swift

func fetchAllPosts(_ query: [String: Any]) {
    getPosts(query)
        .receive(on: DispatchQueue.main)
        .sink { completion in
            switch completion {
            case .failure(let error):
                print("Error: \(error.localizedDescription)")
            case .finished:
                break
            }
        } receiveValue: { model in
            print("Model:", model)
        }
        .store(in: &cancellable)
}

func getPosts(_ query: [String: Any]) -> AnyPublisher<[YourModel], NetworkError> {
    networking.get(
        endPoint: "<your-endpoint>",
        headers: [:],
        query: query,
        modelType: [YourModel].self
    )
}

func createPost() {
    let params: [String: Any] = [
        "title": "Developer",
        "body": "iOS Developer",
        "userId": 1
    ]
    
    networking.post(
        endPoint: "<your-endpoint>",
        params: params,
        headers: [:],
        modelType: YourModel.self
    )
    .receive(on: DispatchQueue.main)
    .sink { completion in
        switch completion {
        case .failure(let error):
            print("Error: \(error.localizedDescription)")
        case .finished:
            break
        }
    } receiveValue: { model in
        print("Model:", model)
    }
    .store(in: &cancellable)
}
```
### 6. Multipart Upload (Image, Video, PDF, etc.)
```swift
func uploadMedia(type: DOCUMENTTYPE, fileURL: URL) {
    do {
        let fileData = try Data(contentsOf: fileURL)
        let postData = PostData(value: fileData, type: type)
        
        let params: [String: Any] = ["file": postData]
        
        networking.multipart(
            endPoint: "<your-endpoint>",
            method: .post,
            parameters: params,
            header: [:]
        ) { progress in
            print("Upload Progress:", progress.fractionCompleted)
        }
        .sink { completion in
            if case .failure(let error) = completion {
                print("Upload failed:", error.localizedDescription)
            }
        } receiveValue: { data, response in
            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode),
               let data = data {
                do {
                    let model = try JSONDecoder().decode(YourModel.self, from: data)
                    print("Model:", model)
                } catch {
                    print("Error:", error.localizedDescription)
                }
            } else {
                print("Invalid upload response")
            }
        }
        .store(in: &cancellables)
        
    } catch {
        print("File read failed:", error.localizedDescription)
    }
}
```
## 📄 License

NetworkingKit is available under the MIT license. See the [LICENSE](./LICENSE) file for more info.
