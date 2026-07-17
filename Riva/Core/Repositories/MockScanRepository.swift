import Foundation

/// Canned scanner for previews and UI work without the network.
struct MockScanRepository: ScanRepository {

    func scan(imageData: Data, mode: ScanMode) async throws -> ScanResult {
        try? await Task.sleep(for: .seconds(1))
        return Self.sampleMeal
    }

    func accept(_ scan: ScanResult) async throws -> DayTotals {
        try? await Task.sleep(for: .milliseconds(400))
        let delta = scan.nutritionDayDelta
        return DayTotals(
            day: "2026-07-17",
            calories: 820 + delta.calories,
            proteinGrams: 41 + delta.proteinGrams,
            carbGrams: 88 + delta.carbGrams,
            fiberGrams: 12 + delta.fiberGrams,
            waterOunces: 24 + delta.waterOunces
        )
    }

    static let sampleMeal = ScanResult(
        scanType: .food,
        requestedMode: "food",
        modeMismatch: false,
        reason: nil,
        plate: "10 inch dinner plate",
        items: [
            ScanItem(
                name: "grilled chicken breast",
                portionDesc: "1 breast, about 6 oz",
                portionGrams: 170,
                confidence: "high",
                calories: 257,
                proteinGrams: 52,
                carbGrams: 0,
                fiberGrams: 0,
                extended: ExtendedNutrients(fatG: 5.4, sugarG: 0, sodiumMg: 126),
                matched: true,
                fdcId: 171534,
                fdcDescription: "Chicken, broiler, breast, grilled",
                source: "usda",
                alternatives: ["roasted turkey breast", "pork chop"]
            ),
            ScanItem(
                name: "steamed broccoli",
                portionDesc: "1 cup",
                portionGrams: 90,
                confidence: "medium",
                calories: 31,
                proteinGrams: 3,
                carbGrams: 6,
                fiberGrams: 2,
                extended: ExtendedNutrients(fatG: 0.3, sugarG: 1.4, sodiumMg: 30),
                matched: false,
                fdcId: nil,
                fdcDescription: nil,
                source: "model",
                alternatives: []
            ),
        ],
        water: nil,
        totals: ScanTotals(calories: 288, proteinGrams: 55, carbGrams: 6, fiberGrams: 2),
        nutritionDayDelta: NutritionDelta(
            calories: 288, proteinGrams: 55, carbGrams: 6, fiberGrams: 2, waterOunces: 0
        ),
        promptVersion: "v1",
        model: "mock"
    )
}

/// Always signed-in auth for previews.
struct MockAuthRepository: AuthRepository {
    func currentSession() async -> AuthSession? {
        AuthSession(
            accessToken: "mock",
            refreshToken: "mock",
            expiresAt: Date().addingTimeInterval(3600),
            userID: "00000000-0000-0000-0000-000000000000",
            email: "preview@riva.app"
        )
    }

    func requestCode(email: String) async throws {}

    @discardableResult
    func verifyCode(email: String, code: String) async throws -> AuthSession {
        await currentSession()!
    }

    func validAccessToken() async throws -> String? { "mock" }

    func signOut() async {}
}
