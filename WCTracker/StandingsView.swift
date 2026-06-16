import SwiftUI

// MARK: - Group standings

/// Full group standings (everything the ESPN standings endpoint returns: rank,
/// played, W/D/L, goals for/against, goal difference, points), as a grid of tables.
struct StandingsView: View {
    @ObservedObject var tournament: TournamentStore

    var body: some View {
        ScrollView {
            if tournament.groups.isEmpty {
                Text("Standings unavailable.")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.top, 60)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 16)],
                          alignment: .leading, spacing: 16) {
                    ForEach(tournament.groups) { group in
                        groupCard(group)
                    }
                }
                .padding(16)
            }
        }
    }

    private func rows(_ group: TournamentGroup) -> [Team] {
        group.inlineTeams.isEmpty ? group.teamIds.compactMap { tournament.team(id: $0) } : group.inlineTeams
    }

    private func groupCard(_ group: TournamentGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.name.count <= 2 ? "Group \(group.name)" : group.name)
                .font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)

            HStack(spacing: 0) {
                Text("Team").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(["P", "W", "D", "L", "GF", "GA", "GD", "Pts"], id: \.self) { h in
                    Text(h).font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                        .frame(width: h == "Pts" ? 34 : 26)
                }
            }
            .padding(.top, 2)

            ForEach(Array(rows(group).enumerated()), id: \.element.id) { idx, t in
                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Text("\(idx + 1)").font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary).frame(width: 16, alignment: .trailing)
                        Text(t.flag)
                        Text(t.code).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        Text(t.name).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    cell(t.played); cell(t.wins); cell(t.draws); cell(t.losses)
                    cell(t.goalsFor); cell(t.goalsAgainst); cell(goalDiff(t))
                    cell(t.points, wide: true, bold: true)
                }
                .padding(.vertical, 5)
                Divider().overlay(.white.opacity(0.08))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 1))
    }

    private func goalDiff(_ t: Team) -> Int? {
        guard let gf = t.goalsFor, let ga = t.goalsAgainst else { return nil }
        return gf - ga
    }

    private func cell(_ value: Int?, wide: Bool = false, bold: Bool = false) -> some View {
        Text(value.map(String.init) ?? "–")
            .font(.system(size: 12, weight: bold ? .heavy : .regular)).monospacedDigit()
            .foregroundStyle(bold ? .white : .white.opacity(0.85))
            .frame(width: wide ? 34 : 26)
    }
}

// MARK: - Per-player stats sheet (tap a player on the pitch)

struct PlayerStatsSheet: View {
    let player: LineupPlayer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Group {
                            if let url = player.headshotURL {
                                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { numberCircle }
                            } else {
                                numberCircle
                            }
                        }
                        .frame(width: 52, height: 52).clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.name).font(.headline)
                            Text("#\(player.number) · \(player.positionAbbr)")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if player.subbedOut {
                                Label("Subbed off", systemImage: "arrow.down.circle.fill")
                                    .font(.caption).foregroundStyle(.red)
                            } else if player.subbedIn {
                                Label("Came on", systemImage: "arrow.up.circle.fill")
                                    .font(.caption).foregroundStyle(.green)
                            }
                        }
                    }
                }

                if player.stats.isEmpty {
                    Text("No match stats available.").foregroundStyle(.secondary)
                } else {
                    Section("Match Stats") {
                        ForEach(player.stats) { s in
                            LabeledContent(s.name.isEmpty ? s.label : s.name, value: s.value)
                        }
                    }
                }
            }
            .navigationTitle(player.shortName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var numberCircle: some View {
        ZStack {
            Circle().fill(Brand.barBlack)
            Text(player.number).font(.system(size: 20, weight: .heavy)).foregroundStyle(.white)
        }
    }
}

// MARK: - Info-card layout editor (order + visibility)

struct CardLayoutEditor: View {
    @ObservedObject var store: MatchCenterStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.cardOrder) { card in
                        Toggle(isOn: Binding(
                            get: { !store.hiddenCards.contains(card) },
                            set: { store.setCard(card, visible: $0) })) {
                            Label(card.title, systemImage: card.systemImage)
                        }
                    }
                    .onMove { store.moveCards(from: $0, to: $1) }
                } footer: {
                    Text("Switch a card off to hide it. Tap Edit, then drag the handles to reorder. Applies to the live match info panel.")
                }
            }
            .navigationTitle("Customize Cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
