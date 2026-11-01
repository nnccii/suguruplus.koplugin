-- suguru_i18n.lua
-- Minimal localisation. Source strings are English; a catalogue is picked from
-- KOReader's UI language (G_reader_settings "language", e.g. "fr" or "fr_FR").
-- Unknown languages and missing entries fall back to English.
--
-- To add a language: add a table below keyed by the English source strings and
-- register it in CATALOGS under its two-letter code.

local fr = {
    -- buttons and menus
    ["New game"] = "Nouvelle partie",
    ["Rules"] = "Règles",
    ["Solution"] = "Solution",
    ["Hide"] = "Masquer",
    ["Close"] = "Fermer",
    ["Erase"] = "Effacer",
    ["Hint"] = "Indice",
    ["Check"] = "Vérifier",
    ["Undo"] = "Annuler",
    ["Cancel"] = "Annuler",
    ["Notes: on"] = "Notes : oui",
    ["Notes: off"] = "Notes : non",
    ["New game: grid size"] = "Nouvelle partie : taille de la grille",
    ["%1×%2: difficulty"] = "%1×%2 : difficulté",
    ["Easy"] = "Facile",
    ["Medium"] = "Moyen",
    ["Hard"] = "Difficile",
    -- status line and messages
    ["%1×%2 %3  ·  empty cells: %4%5"] = "%1×%2 %3  ·  cases vides : %4%5",
    ["  ·  notes mode"] = "  ·  mode notes",
    ["Solution shown: input is locked."] = "Solution affichée : la saisie est bloquée.",
    ["Well done, puzzle solved!"] = "Bravo, grille terminée !",
    ["Move undone."] = "Coup annulé.",
    ["Everything is correct!"] = "Tout est juste !",
    ["Mistakes are marked with a black corner."] = "Les erreurs sont marquées d'un coin noir.",
    ["No mistakes so far, keep going!"] = "Aucune erreur pour l'instant, continue !",
    ["Generating the puzzle…"] = "Génération de la grille…",
    ["Could not generate a puzzle, please try again."] = "Impossible de générer une grille, réessaie.",
    ["Could not generate a puzzle."] = "Impossible de générer une grille.",
    ["New %1×%2 puzzle, %3."] = "Nouvelle grille %1×%2 %3.",
    ["Hide the solution to keep playing."] = "Masque la solution pour continuer.",
    ["This cell is given."] = "Cette case est donnée.",
    ["Cell already empty."] = "Case déjà vide.",
    ["Erase the cell before adding notes."] = "Efface la case avant d'ajouter des notes.",
    ["Nothing to undo."] = "Rien à annuler.",
    ["This cell is wrong: erase it."] = "Cette case est fausse : efface-la.",
    ["No simple deduction found."] = "Aucune déduction simple trouvée.",
    ["Hint: a %1 goes here, %2."] = "Indice : un %1 va ici, %2.",
    ["because it is the only digit possible in this cell, or the only place for this digit in its block"] =
        "car c'est le seul chiffre possible dans cette case, ou la seule place pour ce chiffre dans sa zone",
    ["found by trying every way to fill the neighbouring blocks"] =
        "on le trouve en essayant toutes les façons de remplir les zones voisines",
    -- rules
    ["RULES_TEXT"] = [[Suguru

Le but est de remplir toutes les cases avec des chiffres.

1. Les traits épais découpent la grille en zones.
2. Une zone de 2 cases contient 1 et 2. Une zone de 3 cases contient 1, 2 et 3. Et ainsi de suite jusqu'à 5.
3. Deux cases qui se touchent, même par un coin, n'ont jamais le même chiffre.

Les chiffres en gras sont donnés au départ. Il n'y a qu'une solution, et on la trouve sans jamais deviner.]],
}

-- English text for long entries referenced by key.
local en_long = {
    ["RULES_TEXT"] = [[Suguru

The goal is to fill every cell with a digit.

1. Thick lines divide the grid into blocks.
2. A block of 2 cells contains 1 and 2. A block of 3 cells contains 1, 2 and 3. And so on, up to 5.
3. Two cells that touch, even at a corner, never contain the same digit.

Bold digits are given at the start. There is only one solution, and it can be found without ever guessing.]],
}

local CATALOGS = { fr = fr }

local M = { missing = {} }

function M.detectLanguage()
    local lang
    if G_reader_settings and G_reader_settings.readSetting then
        lang = G_reader_settings:readSetting("language")
    end
    if type(lang) ~= "string" then
        return "en"
    end
    return (lang:match("^(%a%a)") or "en"):lower()
end

function M.setLanguage(code)
    M.lang = code
    M.catalog = CATALOGS[code]
end

M.setLanguage(M.detectLanguage())

-- Translates an English source string (or a long-text key).
function M.translate(s)
    local catalog = M.catalog
    if catalog then
        local t = catalog[s]
        if t then
            return t
        end
        M.missing[s] = true -- recorded so tests can catch untranslated strings
    end
    return en_long[s] or s
end

return setmetatable(M, { __call = function(_, s) return M.translate(s) end })
