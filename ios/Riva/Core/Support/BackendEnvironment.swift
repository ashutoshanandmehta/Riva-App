import Foundation

/// Endpoints and public keys for the Riva backend.
///
/// The Supabase anon key is public by design: it only grants what Row Level
/// Security allows, and every write goes through the scan service with the
/// user's verified token. Secrets never ship in the app.
enum BackendEnvironment {

    /// The scan service (vision pipeline plus logging API).
    static var scanServiceURL: URL {
        #if DEBUG
        // Point a debug build at a local server:
        // -riva.scanService http://192.168.1.20:8000
        if let override = UserDefaults.standard.string(forKey: "riva.scanService"),
           let url = URL(string: override) {
            return url
        }
        #endif
        return URL(string: "https://riva-snap.onrender.com")!
    }

    /// Supabase project (auth only; data writes go through the scan service).
    static let supabaseURL = URL(string: "https://casmdqfgxoihjisrjsbk.supabase.co")!

    /// Google sign in runs through Supabase's OAuth flow in a system web
    /// session; the tokens come back on this custom scheme redirect.
    /// (ASWebAuthenticationSession intercepts it, so the scheme needs no
    /// Info.plist registration.)
    static let oauthCallbackScheme = "riva-auth"
    static var googleAuthorizeURL: URL {
        URL(
            string: "auth/v1/authorize?provider=google&redirect_to=\(oauthCallbackScheme)://callback",
            relativeTo: supabaseURL
        )!
    }
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNhc21kcWZneG9paGppc3Jqc2JrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQyOTA1NDQsImV4cCI6MjA5OTg2NjU0NH0.o4KhfXFdm0mlDG4QxOFb4JFvlCQrNlnYSFyXqvLci8k"
}
