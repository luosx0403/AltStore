import Foundation

// Only the imported model/crypto dependencies are fixtures. The authentication
// state machine and request builders below come from the production source.
public let ALTSourceFileErrorKey = "sourceFile"
public let ALTSourceLineErrorKey = "sourceLine"
public let ALTUnderlyingAppleAPIErrorDomain = "fixture.AppleAPI"
public struct ALTAppleAPIError: Error {
    public enum Code { case unknown, authenticationHandshakeFailed, requiresTwoFactorAuthentication, incorrectVerificationCode, incorrectCredentials, invalidAnisetteData }
    let code: Code
    public init(_ code: Code, userInfo: [String: Any] = [:]) { self.code = code }
}
public class ALTAccount: NSObject {
    init(responseDictionary: [String: Any]) {}
}
public class ALTAnisetteData: NSObject {
    var machineID = "fixture-machine"
    var oneTimePassword = "fixture-otp"
    var deviceUniqueIdentifier = "fixture-device"
    var localUserID = "fixture-local-user"
    var routingInfo: UInt64 = 17106176
    var deviceSerialNumber = "fixture-serial"
    var deviceDescription = "<MacBookPro18,3> <macOS;26.6;25F84> <com.apple.AuthKit/1 (com.apple.akd/1.0)>"
    var date = Date()
    var locale = Locale(identifier: "en_US")
    var timeZone = TimeZone(secondsFromGMT: 0)!
}
public class ALTAppleAPISession: NSObject {
    init(dsid: String, authToken: String, anisetteData: ALTAnisetteData) {}
}
public class ALTAppleAPI: NSObject {
    let session = URLSession(configuration: fixtureConfiguration())
    let dateFormatter = ISO8601DateFormatter()
    let baseURL = URL(string: "https://fixture.invalid/")!
    func sendRequest(with url: URL, additionalParameters: Any?, session: ALTAppleAPISession, team: Any?, completion: ([String: Any]?, Error?) -> Void) {
        completion(["developer": [:]], nil)
    }
    func processResponse(_ dictionary: [String: Any], parseHandler: () -> Any?, resultCodeHandler: Any?) throws -> Any? { parseHandler() }
}
final class GSAContext {
    var salt = Data(), serverPublicKey = Data(), dsid = "", sessionKey = Data()
    init(username: String, password: String) {}
    func start() -> Data? { Data([1]) }
    func makeVerificationMessage(iterations: Int, isHexadecimal: Bool) -> Data? { Data([2]) }
    func verifyServerVerificationMessage(_ data: Data) -> Bool { true }
    func makeChecksum(appName: String) -> Data? { Data([3]) }
}
extension Data {
    func decryptedCBC(context: GSAContext) -> Data? { self }
    func decryptedGCM(context: GSAContext) -> Data? { self }
}
func fixtureConfiguration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FixtureProtocol.self]
    return configuration
}
final class FixtureProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, [String: String], Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, headers, data) = try Self.handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client!.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client!.urlProtocol(self, didLoad: data)
            client!.urlProtocolDidFinishLoading(self)
        } catch { client!.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
func plist(_ value: [String: Any]) -> Data {
    try! PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
}
func requestBody(_ request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data(), buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(contentsOf: buffer.prefix(count))
    }
    return data
}
func require(_ value: Bool, _ message: String) {
    if !value {
        FileHandle.standardError.write(Data("FAIL \(message)\n".utf8))
        exit(1)
    }
}
func runCase(_ name: String, status: [String: Any], expectTrustedRequest: Bool = false,
             expectSMS: Bool = false, suppliedCode: String? = "123456",
             hasHandler: Bool = true, validationError: Bool = false,
             serverHTTP: Int = 200, serverError: Int = 0,
             expectedError: ALTAppleAPIError.Code? = nil, underlyingError: Int? = nil) {
    let api = ALTAppleAPI(), anisette = ALTAnisetteData()
    let originalDescription = anisette.deviceDescription
    let android = "<Pixel 5> <Android;11;RQ3A.211001.001> <com.apple.AuthKit/1 (com.apple.akd/1.0)>"
    var validated = false, trustedRequests = 0, smsRequests = 0, verificationRequests = 0, prompts = 0, appTokens = 0
    let completion = DispatchSemaphore(value: 0)
    var finished = false, resultError: Error?
    FixtureProtocol.handler = { request in
        let path = request.url!.path
        if path == "/grandslam/GsService2" {
            let expectedInfo: String
            if #available(macOS 27, *) { expectedInfo = android } else { expectedInfo = originalDescription }
            require(request.value(forHTTPHeaderField: "X-MMe-Client-Info") == expectedInfo, "GrandSlam identity")
            require(request.value(forHTTPHeaderField: "User-Agent") == "AuthKit/1 (Macintosh; OS X 26.5.2) (com.apple.dt.Xcode/26.0)", "Existing 503 User-Agent changed")
            require(request.httpMethod == "POST", "GrandSlam method")
            if serverHTTP >= 500 { return (serverHTTP, [:], Data("<html>unavailable</html>".utf8)) }
            if serverError != 0 { return (200, [:], plist(["Response": ["Status": ["ec": serverError, "em": "fixture error"]]])) }
            let body = try PropertyListSerialization.propertyList(from: requestBody(request), format: nil) as! [String: Any]
            require((body["Header"] as! [String: String])["Version"] == "1.0.1", "Protocol version changed")
            let parameters = body["Request"] as! [String: Any]
            let operation = parameters["o"] as! String
            switch operation {
            case "init":
                return (200, [:], plist(["Response": ["Status": ["ec": 0], "c": "challenge", "s": Data([1]), "i": 1, "B": Data([2]), "sp": "s2k"]]))
            case "complete":
                let secrets: [String: Any] = ["adsid": "fixture-dsid", "GsIdmsToken": "fixture-idms", "sk": Data([1]), "c": Data([2])]
                return (200, [:], plist(["Response": ["Status": validated ? ["ec": 0, "hsc": 200] : status, "M2": Data([1]), "spd": plist(secrets)]]))
            case "apptokens":
                appTokens += 1
                return (200, [:], plist(["Response": ["Status": ["ec": 0], "et": plist(["t": ["com.apple.gs.xcode.auth": ["token": "fixture-token"]]])]]))
            default: fatalError("Unexpected GrandSlam operation")
            }
        }
        require(request.value(forHTTPHeaderField: "X-MMe-Client-Info") == originalDescription, "2FA must keep Mac identity")
        if path == "/auth/verify/trusteddevice" {
            trustedRequests += 1
            return (200, [:], Data())
        }
        if path == "/grandslam/GsService2/validate" {
            verificationRequests += 1
            require(request.value(forHTTPHeaderField: "security-code") == "123456", "Code not passed to validation")
            validated = !validationError
            return (200, [:], plist(["ec": validationError ? -21669 : 0]))
        }
        if path == "/auth/verify/phone/put" {
            smsRequests += 1
            require(request.httpMethod == "POST", "SMS method")
            return (200, [:], Data())
        }
        if path == "/auth/verify/phone/securitycode" {
            verificationRequests += 1
            validated = true
            return (200, ["X-Apple-PE-Token": "fixture-pe"], Data())
        }
        fatalError("Unexpected URL: \(path)")
    }
    var handler: ((@escaping (String?) -> Void) -> Void)?
    if hasHandler { handler = { reply in prompts += 1; reply(suppliedCode) } }
    api.authenticate(appleID: "FIXTURE@example.invalid", password: "fixture-password", anisetteData: anisette, verificationHandler: handler) { account, session, error in
        finished = account != nil && session != nil
        resultError = error
        completion.signal()
    }
    require(completion.wait(timeout: .now() + 10) == .success, "Callback timeout: \(name)")
    if let expectedError {
        require((resultError as? ALTAppleAPIError)?.code == expectedError, "Wrong error: \(name)")
        require(!finished && appTokens == 0, "Authentication continued after failure")
    } else if let underlyingError {
        require((resultError as NSError?)?.code == underlyingError, "Wrong underlying error")
        require(!finished && appTokens == 0, "Authentication continued after failure")
    } else {
        require(finished && resultError == nil && appTokens == 1, "Login didn't finish: \(name)")
    }
    require(trustedRequests == (expectTrustedRequest ? 1 : 0), "Wrong trusted-device requests: \(name)")
    require(smsRequests == (expectSMS ? 1 : 0), "Wrong SMS requests: \(name)")
    require(verificationRequests == (prompts == 1 && suppliedCode != nil ? 1 : 0), "Wrong verification requests: \(name)")
    require(prompts == ((hasHandler && (status["hsc"] as? Int == 409 || status["au"] != nil) && serverHTTP < 500 && serverError == 0) ? 1 : 0), "Wrong prompt count: \(name)")
    require(anisette.deviceDescription == originalDescription, "Shared anisette identity mutated")
    api.session.invalidateAndCancel()
    print("PASS \(name)")
}
func runRegressionTests() {
    runCase("409 without au skips resend and completes login", status: ["ec": 0, "hsc": 409])
    runCase("409 with empty au skips resend", status: ["ec": 0, "hsc": 409, "au": ""])
    runCase("explicit trusted-device auth still requests code", status: ["ec": 0, "au": "trustedDeviceSecondaryAuth"], expectTrustedRequest: true)
    runCase("explicit SMS wins over 409 and keeps Mac headers", status: ["ec": 0, "hsc": 409, "au": "secondaryAuth"], expectSMS: true)
    runCase("normal login without 2FA still works", status: ["ec": 0, "hsc": 200])
    runCase("409 without UI reports 2FA requirement", status: ["ec": 0, "hsc": 409], hasHandler: false, expectedError: .requiresTwoFactorAuthentication)
    runCase("cancelled prompt stops login", status: ["ec": 0, "hsc": 409], suppliedCode: nil, expectedError: .requiresTwoFactorAuthentication)
    runCase("incorrect code stops login", status: ["ec": 0, "hsc": 409], validationError: true, expectedError: .incorrectVerificationCode)
    runCase("503 HTML remains an HTTP error", status: ["ec": 0], serverHTTP: 503, expectedError: .unknown)
    runCase("server -80045 still propagates", status: ["ec": 0], serverError: -80045, underlyingError: -80045)
    runCase("incorrect credentials still propagate", status: ["ec": 0], serverError: -20101, expectedError: .incorrectCredentials)
    print("11 offline authentication regression cases passed.")
}
