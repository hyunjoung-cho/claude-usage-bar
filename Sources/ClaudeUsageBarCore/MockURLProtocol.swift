import Foundation

/// URLSession test helper — register as `URLSessionConfiguration.protocolClasses`
/// and set `MockURLProtocol.responder` to a closure that returns (HTTPURLResponse, Data).
public final class MockURLProtocol: URLProtocol {
    public static var responder: ((URLRequest) -> (HTTPURLResponse, Data))?
    public static func reset() { responder = nil }

    public override class func canInit(with request: URLRequest) -> Bool { true }
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    public override func startLoading() {
        guard let responder = Self.responder else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let (resp, data) = responder(request)
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    public override func stopLoading() {}
}
