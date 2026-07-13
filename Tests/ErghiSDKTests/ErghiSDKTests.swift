import XCTest
@testable import ErghiSDK
import Combine

final class ErghiSDKTests: XCTestCase {
    var client: ErghiClient!
    var config: ErghiConfig!
    var cancellables = Set<AnyCancellable>()
    
    override func setUp() {
        super.setUp()
        config = ErghiConfig(
            apiURL: URL(string: "https://api.test.com")!,
            wsURL: URL(string: "wss://api.test.com")!
        )
        client = ErghiClient(config: config)
    }
    
    override func tearDown() {
        client = nil
        config = nil
        cancellables.removeAll()
        super.tearDown()
    }
    
    func testInitialization() {
        XCTAssertEqual(client.config.apiURL.absoluteString, "https://api.test.com")
        XCTAssertFalse(client.isConnected)
    }
    
    func testResourcesAvailable() {
        XCTAssertNotNil(client.auth)
        XCTAssertNotNil(client.chat)
    }
    
    func testWebSocketDerivation() {
        let httpsConfig = ErghiConfig(apiURL: URL(string: "https://api.erghi.ai")!)
        XCTAssertEqual(httpsConfig.websocketURL.absoluteString, "wss://api.erghi.ai")
        
        let httpConfig = ErghiConfig(apiURL: URL(string: "http://localhost:5000")!)
        XCTAssertEqual(httpConfig.websocketURL.absoluteString, "ws://localhost:5000")
        
        let explicitWSConfig = ErghiConfig(
            apiURL: URL(string: "https://api.erghi.ai")!,
            wsURL: URL(string: "wss://custom.socket.io")!
        )
        XCTAssertEqual(explicitWSConfig.websocketURL.absoluteString, "wss://custom.socket.io")
    }
}
