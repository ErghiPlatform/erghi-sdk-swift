import Foundation
import Alamofire

internal final class M2MRequestInterceptor: RequestInterceptor, @unchecked Sendable {
    private let config: ErghiConfig
    internal var auth: AuthResource?
    private let lock = NSLock()
    private var isAuthenticating = false
    
    init(config: ErghiConfig) {
        self.config = config
    }
    
    func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        var request = urlRequest
        
        if let apiKey = config.apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }
        
        if let workspaceId = config.workspaceId {
            request.setValue(workspaceId, forHTTPHeaderField: "X-Workspace-Id")
        }
        
        if let accountId = config.accountId {
            request.setValue(accountId, forHTTPHeaderField: "X-Account-Id")
        }
        
        if request.url?.path.contains("/api/v1/auth/token") == true {
            completion(.success(request))
            return
        }
        
        if let accessToken = auth?.accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            completion(.success(request))
            return
        }
        
        if config.clientId != nil && config.clientSecret != nil {
            authenticate { result in
                switch result {
                case .success(let token):
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    completion(.success(request))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
            return
        }
        
        completion(.success(request))
    }
    
    private func authenticate(completion: @escaping (Result<String, Error>) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        
        guard let clientId = config.clientId, let clientSecret = config.clientSecret else {
            completion(.failure(ErghiError.authenticationFailed("Missing client credentials")))
            return
        }
        
        if let accessToken = auth?.accessToken {
            completion(.success(accessToken))
            return
        }
        
        isAuthenticating = true
        
        let url = config.apiURL.appendingPathComponent("api/v1/auth/token")
        let parameters: [String: String] = [
            "grant_type": "client_credentials",
            "client_id": clientId,
            "client_secret": clientSecret
        ]
        
        AF.request(url, method: .post, parameters: parameters, encoder: JSONParameterEncoder.default).responseDecodable(of: TokenResponse.self) { [weak self] response in
            guard let self = self else { return }
            self.lock.lock()
            self.isAuthenticating = false
            self.lock.unlock()
            
            switch response.result {
            case .success(let tokenResponse):
                self.auth?.storeM2MToken(tokenResponse.accessToken)
                completion(.success(tokenResponse.accessToken))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}
