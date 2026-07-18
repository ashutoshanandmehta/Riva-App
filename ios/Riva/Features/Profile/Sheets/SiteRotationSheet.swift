import SwiftUI

/// Read-only rotation guide: when each injection site was last used and
/// which one to use next.
struct SiteRotationSheet: View {
    let onClose: () -> Void

    @State private var model: SiteRotationViewModel

    init(account: any AccountRepository, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _model = State(initialValue: SiteRotationViewModel(account: account))
    }

    var body: some View {
        VStack(spacing: RivaSpacing.lg) {
            AccountSheetHeader(sheet: .siteRotation)

            switch model.phase {
            case .loading:
                Spacer()
                ProgressView()
                Spacer()
            case .failed(let message):
                AccountLoadFailedView(message: message) {
                    Task { await model.load() }
                }
            case .ready(let statuses, let suggested):
                siteList(statuses, suggested: suggested)
                Spacer(minLength: RivaSpacing.xs)
                Button("Done", action: onClose)
                    .buttonStyle(.rivaPrimary)
                    .padding(.horizontal, RivaSpacing.screenMargin)
            }
        }
        .padding(.top, RivaSpacing.xl)
        .padding(.bottom, RivaSpacing.lg)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(RivaColor.background)
        .task { await model.load() }
    }

    private func siteList(
        _ statuses: [SiteRotationViewModel.SiteStatus], suggested: InjectionSite
    ) -> some View {
        ScrollView {
            VStack(spacing: RivaSpacing.xs) {
                Text("Rotating where you inject gives each spot time to recover, which keeps shots comfortable and absorption steady.")
                    .font(RivaFont.footnote)
                    .foregroundStyle(RivaColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, RivaSpacing.xxs)

                ForEach(statuses) { status in
                    siteRow(status, isSuggested: status.site == suggested)
                }
            }
            .padding(.horizontal, RivaSpacing.screenMargin)
        }
    }

    private func siteRow(
        _ status: SiteRotationViewModel.SiteStatus, isSuggested: Bool
    ) -> some View {
        HStack(spacing: RivaSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(status.site.title)
                    .font(RivaFont.cardTitle)
                    .foregroundStyle(RivaColor.textPrimary)
                Text(status.subtitle)
                    .font(RivaFont.footnote)
                    .foregroundStyle(RivaColor.textSecondary)
            }
            Spacer()
            if isSuggested {
                RivaBadge(text: "Suggested", style: .brand)
            }
        }
        .padding(RivaSpacing.sm)
        .background(
            isSuggested ? RivaColor.brandWash : RivaColor.surface,
            in: RoundedRectangle(cornerRadius: RivaRadius.tile, style: .continuous)
        )
        .rivaSurfaceOutline(cornerRadius: RivaRadius.tile)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isSuggested
                ? "\(status.site.title), \(status.subtitle), suggested next site"
                : "\(status.site.title), \(status.subtitle)"
        )
    }
}

/// Reads the shot history and works out each site's last use and the
/// suggested next site: never used first, else least recently used.
@MainActor
@Observable
final class SiteRotationViewModel {

    struct SiteStatus: Identifiable, Equatable {
        let site: InjectionSite
        let lastUsed: Date?

        var id: String { site.id }

        var subtitle: String {
            guard let lastUsed else { return "Never used" }
            let calendar = Calendar.current
            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: lastUsed),
                to: calendar.startOfDay(for: .now)
            ).day ?? 0
            switch days {
            case ...0: return "Used today"
            case 1: return "Last used yesterday"
            default: return "Last used \(days) days ago"
            }
        }
    }

    enum Phase: Equatable {
        case loading
        case failed(String)
        case ready([SiteStatus], suggested: InjectionSite)
    }

    private(set) var phase: Phase = .loading

    private let account: any AccountRepository

    init(account: any AccountRepository) {
        self.account = account
    }

    func load() async {
        phase = .loading
        do {
            let shots = try await account.shots()
            let statuses = InjectionSite.allCases.map { site in
                // Shots come newest first, so the first match is the latest use.
                SiteStatus(
                    site: site,
                    lastUsed: shots.first { $0.injectionSite == site.rawValue }
                        .flatMap { AccountDates.timestamp($0.takenAt) }
                )
            }
            let suggested = statuses.first { $0.lastUsed == nil }?.site
                ?? statuses.min { ($0.lastUsed ?? .now) < ($1.lastUsed ?? .now) }?.site
                ?? .leftArm
            phase = .ready(statuses, suggested: suggested)
        } catch is CancellationError {
            // Sheet dismissed mid-load; nothing to surface.
        } catch {
            phase = .failed("Could not load your shot history.")
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        SiteRotationSheet(account: MockAccountRepository()) {}
    }
}
