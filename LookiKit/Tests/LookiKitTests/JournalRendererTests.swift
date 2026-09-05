import Testing
import Foundation
@testable import LookiKit

@Suite struct JournalRendererTests {
    @Test func rendersGoldenJournal() throws {
        let moments = try #require(try LookiJSON.decoder().decode(Envelope<[Moment]>.self, from: Fixture.data("moments-day")).data)
        let generated = try #require(LookiJSON.parseDate("2026-09-05T18:30:00.000000+02:00"))
        let md = JournalRenderer.render(day: DayKey(year: 2026, month: 9, day: 5), moments: moments, generatedAt: generated)

        let expected = """
        # Journal Looki — samedi 5 septembre 2026

        > 2 moments · 09:59 → 13:46 · 1 h 14 enregistrées · Paris

        ## Chronologie

        | Heure | Moment | Lieu | Média |
        |---|---|---|---|
        | 09:59–10:03 | [Promenade au parc](#aaaaaaaa) | Rue du Parc, 75000 Paris, France | vidéo |
        | 12:35–13:46 | [Déjeuner en terrasse](#aaaaaaaa) | Place du Marché 3, 75000 Paris, France | photo, vidéo |

        ## Récit de la journée

        ### 09:59 · Promenade au parc <a id="aaaaaaaa"></a>

        *09:59–10:03 (3 min) · Rue du Parc, 75000 Paris, France*

        L'utilisateur marche dans un parc ensoleillé, longe un étang et croise des joggeurs.

        ### 12:35 · Déjeuner en terrasse <a id="aaaaaaaa"></a>

        *12:35–13:46 (1 h 10) · Place du Marché 3, 75000 Paris, France*

        Repas partagé en terrasse, discussion animée autour d'un plat de pâtes.

        ---

        *Généré depuis l'API Looki (`GET /moments?on_date=2026-09-05`) le 2026-09-05 18:30. Identifiants des moments : `aaaaaaaa-0000-4000-8000-000000000001`, `aaaaaaaa-0000-4000-8000-000000000002`.*

        """
        #expect(md == expected)
    }

    @Test func emptyDayStillRenders() {
        let md = JournalRenderer.render(day: DayKey(year: 2026, month: 9, day: 6), moments: [], generatedAt: Date(timeIntervalSince1970: 0))
        #expect(md.contains("# Journal Looki — dimanche 6 septembre 2026"))
        #expect(md.contains("> 0 moment · aucune capture ce jour"))
        #expect(!md.contains("## Chronologie"))
    }

    @Test func sortsByStartTime() throws {
        var moments = try #require(try LookiJSON.decoder().decode(Envelope<[Moment]>.self, from: Fixture.data("moments-day")).data)
        moments.reverse()
        let md = JournalRenderer.render(day: DayKey(year: 2026, month: 9, day: 5), moments: moments, generatedAt: Date(timeIntervalSince1970: 0))
        let parc = md.range(of: "### 09:59")!.lowerBound
        let dej = md.range(of: "### 12:35")!.lowerBound
        #expect(parc < dej)
    }
}
