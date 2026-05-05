/**
 * Revue courte guidée du module app Zenith via l’agent local Cursor (SDK).
 * Utile avant release ou grosse PR Swift : même dépôt que Xcode, sans copier-coller le contexte à la main.
 */
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { Agent, CursorAgentError } from "@cursor/sdk";

const __dirname = dirname(fileURLToPath(import.meta.url));
const defaultRepoRoot = join(__dirname, "..", "..", "..");

function repoRoot(): string {
  const fromEnv = process.env.ZENITH_REPO_ROOT?.trim();
  if (fromEnv) return fromEnv;
  return defaultRepoRoot;
}

const PROMPT = `Tu analyses le dépôt Zenith : application macOS SwiftUI pour flux photo local (SwiftData, développement non destructif via Core Image, histogramme, export par lot).

Scope strict : parcours surtout le dossier Zenith/Zenith/ (code app). Ne résume pas le README ; base-toi sur le code.

Réponds en français avec cette structure :
1) Données et persistance (SwiftData, modèles, sauvegardes/export catalogue)
2) Performance et thread principal (SwiftUI, Core Image, miniatures, histogramme)
3) Fichiers et sandbox (signets sécurisés, import/export, chemins utilisateur)
4) Jalons de test manuel avant une release

Contraintes : pas de formules de politesse, maximum 12 puces au total, cite des fichiers ou types réels du repo lorsque pertinent. Si une section ne trouve rien de notable, indique-le en une courte phrase.`;

async function main(): Promise<void> {
  if (!process.env.CURSOR_API_KEY?.trim()) {
    console.error(
      "CURSOR_API_KEY manquant. Ajoute une clé API Cursor (dashboard Cloud Agents ou compte équipe), puis relance.\n" +
        "Exemple : export CURSOR_API_KEY='cursor_…'",
    );
    process.exit(1);
  }

  const cwd = repoRoot();
  console.error(`[preflight] cwd=${cwd}`);

  try {
    const result = await Agent.prompt(PROMPT, {
      apiKey: process.env.CURSOR_API_KEY,
      model: { id: "composer-2" },
      local: { cwd },
    });

    if (result.status === "finished") {
      console.log(result.result ?? "");
      process.exit(0);
    }

    console.error(`[preflight] run ${result.id} terminé avec statut ${result.status}`);
    process.exit(2);
  } catch (err) {
    if (err instanceof CursorAgentError) {
      console.error(`[preflight] échec au démarrage : ${err.message} (retryable=${err.isRetryable})`);
      process.exit(1);
    }
    throw err;
  }
}

await main();
