# =============================================================================
# sampling_group.R -- shared sampling-group classifier
# =============================================================================
#
# `sampling_group` sets the shared-effort denominator, one kernel fit per
# group, and each group's own dark-diversity floor (TaxaExpect). Before this
# file existed, its definition was an inline dplyr::case_when() duplicated
# across five workflow files (PtConception 18S, PtConception 12S, GreatLakes,
# the shared template, and CaliforniaIntertidal), and it drifted three times
# before this fix, each caught only by running real data: ray-finned fishes +
# Elasmobranchii missing (2026-09-03, 484,072 records, 54% of the largest
# group), Phaeophyceae missing (2026-09-06, 11,605 records), Dinophyceae
# missing (2026-09-06, 1,192 records), and Bacillariophyceae + Copepoda
# missing (2026-09-13, 2,773 + 66 records). This file exists to end that
# pattern: ONE classifier, ONE scheme object, package-tested.
#
# The logic below is ported, clause for clause, from
# PtConceptionWorkflow_18S_2_single_site.R's Step 4 case_when() (the fullest
# inline version, with the comments explaining why each clause is written the
# way it is) -- see that file's own comments for the fish/Elasmobranchii,
# Phaeophyceae, and Dinophyceae discovery stories. Two additions are new here,
# both dated 2026-09-13 -- see default_sampling_scheme()'s own comments.

# =============================================================================
# default_sampling_scheme()
# =============================================================================

#' Default Sampling-Group Classification Scheme
#'
#' Returns the package's default sampling-group scheme: an ORDERED list of
#' rules (first-match-wins, exactly like the \code{dplyr::case_when()} it
#' replaces) that classifies a taxon's kingdom/phylum/class/order into one of
#' eleven detection-process groups, or a catch-all. Ported clause-for-clause
#' from \code{PtConceptionWorkflow_18S_2_single_site.R}'s Step 4 (the fullest,
#' best-commented inline version of this classifier), with two 2026-09-13
#' additions (see Details).
#'
#' @section Shape:
#' The returned object is a list with three elements:
#' \describe{
#'   \item{\code{rules}}{An ORDERED list of rules. Each rule is
#'     \code{list(group = "<name>", when = list(<clause>, <clause>, ...))}.
#'     The \code{when} clauses are OR'd together (a rule fires if ANY clause
#'     matches); a clause is a named list mapping a rank
#'     (\code{kingdom}/\code{phylum}/\code{class}/\code{order}) to a character
#'     vector of values, and the ranks WITHIN one clause are AND'd together. A
#'     literal \code{NA} as a clause's value for a rank means "this rank is
#'     missing" (\code{is.na()}), not "match nothing" -- this is what lets the
#'     class-less-Chordata fish clause (\code{phylum == "Chordata"} AND
#'     \code{class} missing) be expressed faithfully. Example:
#'     \preformatted{
#'     list(
#'       group = "fishes",
#'       when = list(
#'         list(class = c("Actinopteri", "Elasmobranchii", ...)),
#'         list(phylum = "Chordata", class = NA)
#'       )
#'     )
#'     }
#'   }
#'   \item{\code{catch_all}}{The group name used when no rule matches
#'     (\code{"macroinvertebrates"}).}
#'   \item{\code{kingdom_guard_vocabulary}}{Character vector of kingdom values
#'     considered "animal" for the kingdom guard (see
#'     \code{\link{assign_sampling_group}}'s \code{kingdom_guard} argument):
#'     \code{c("Animalia", "Metazoa")}.}
#' }
#'
#' @section First-match-wins contract:
#' \code{rules} is evaluated top to bottom, exactly like a
#' \code{dplyr::case_when()}: a row is assigned to the FIRST rule whose
#' \code{when} clauses match, and every later rule is skipped for that row --
#' even if a later rule would also have matched. This is a real, load-bearing
#' property of the original classifier (e.g. a taxon that matches both a
#' specific rule and a later, broader one always takes the specific one), and
#' \code{\link{assign_sampling_group}} preserves it exactly.
#'
#' @section The 2026-09-13 fixes:
#' Two real gaps, found the same way as the three earlier drift incidents
#' (running the classifier against real data and reading what fell through to
#' the catch-all):
#' \itemize{
#'   \item \strong{Bacillariophyceae (diatoms) -> \code{"phytoplankton"}}
#'     (2,773 real records). \strong{Trap}: GBIF places diatoms in phylum
#'     \strong{Ochrophyta}, the SAME phylum as the kelps/rockweeds
#'     (Phaeophyceae, classified as \code{"macroalgae"} above). A phylum-level
#'     rule for either group would be wrong in one direction or the other --
#'     it would either exclude the diatoms or admit the kelps into the wrong
#'     group. This MUST be a class-level rule, and it is: the diatom clause
#'     names \code{class = "Bacillariophyceae"} only, never
#'     \code{phylum = "Ochrophyta"}.
#'   \item \strong{Copepoda -> \code{"zooplankton"}} (66 real records on the
#'     dataset where this was found; 36 on the bundled regression checkpoint).
#'     GBIF's current backbone names this class \code{"Hexanauplia"} (already
#'     in the zooplankton clause, per the original 18S file); NCBI's backbone
#'     names it \code{"Copepoda"}. Both spellings are added to the SAME
#'     zooplankton clause, so the classifier works whichever backbone the
#'     input taxonomy came from. Note \code{"Copepoda"} was ALSO found live in
#'     real GBIF-backbone occurrence data (not just NCBI match objects) during
#'     this fix's own regression check -- it is not purely an NCBI artifact,
#'     which is why it is added to the rule directly rather than only handled
#'     via \code{harmonise = TRUE}.
#' }
#'
#' @return A sampling-group scheme object; see Shape above.
#' @seealso \code{\link{assign_sampling_group}}
#' @export
#'
#' @examples
#' scheme <- default_sampling_scheme()
#' length(scheme$rules)
#' scheme$catch_all
default_sampling_scheme <- function() {
  list(
    rules = list(
      # Seagrasses (Zosteraceae, Posidoniaceae, etc.)
      list(
        group = "sea_grasses",
        when = list(list(order = "Alismatales"))
      ),

      # Vascular & non-vascular land plants.
      #
      # "Liliopsida" (the monocots) added 2026-09-13 after the kingdom guard
      # made the gap visible: 114,744 real records -- 5.25% of the Point
      # Conception occurrence pool, the second-largest miscount found in this
      # scheme's history -- were falling through every clause into the
      # "macroinvertebrates" catch-all. It read as covered because the
      # seagrass rule above catches the monocot order Alismatales, so the
      # plant clause LOOKED like it handled monocots while listing only the
      # dicots (Magnoliopsida), gymnosperms, ferns and bryophytes.
      #
      # ORDERING MATTERS AND IS LOAD-BEARING: a seagrass carries BOTH class
      # Liliopsida and order Alismatales (verified live against GBIF's
      # backbone for Zostera marina, Phyllospadix torreyi and Posidonia
      # oceanica), so it is only the first-match-wins contract that keeps
      # seagrasses in "sea_grasses" rather than being swept in here. Do not
      # reorder these two rules. The records this clause newly claims are the
      # other monocot orders -- Poales (Poa, Carex), Arecales (Washingtonia)
      # and the rest.
      list(
        group = "other_vascular_plants",
        when = list(list(class = c(
          "Magnoliopsida", "Liliopsida", "Pinopsida", "Cycadopsida",
          "Polypodiopsida", "Lycopodiopsida", "Bryopsida", "Sphagnopsida",
          "Marchantiopsida", "Jungermanniopsida", "Anthocerotopsida",
          "Haplomitriopsida"
        )))
      ),

      # Macroalgae (benthic seaweeds -- red/green/charophyte/brown).
      # "Phaeophyceae" (brown algae/kelp -- Ochrophyta under GBIF's current
      # backbone, e.g. Sargassum/Undaria) was entirely absent from this
      # clause until 2026-09-06, silently misclassifying 11,605 real records
      # as "macroinvertebrates".
      list(
        group = "macroalgae",
        when = list(list(class = c(
          "Florideophyceae", "Bangiophyceae", "Compsopogonophyceae",
          "Ulvophyceae", "Charophyceae", "Phaeophyceae"
        )))
      ),

      # Phytoplankton / microalgae. "Dinophyceae" (dinoflagellates --
      # Myzozoa under GBIF's current backbone) was entirely absent until
      # 2026-09-06, silently misclassifying 1,192 real records.
      #
      # "Bacillariophyceae" (diatoms) added 2026-09-13, 2,773 real records.
      #
      # SPELLING CORRECTED 2026-09-13: this clause carried "Zygnemophyceae",
      # which matches NOTHING in GBIF's backbone -- name_backbone() returns no
      # match for it at all, so the entry had never caught a single record
      # since it was written. GBIF's accepted class is "Zygnematophyceae"
      # (verified live, and via Spirogyra communis -> class Zygnematophyceae,
      # order Zygnematales). Replaced rather than listed alongside: the old
      # string is not an alternative spelling in use anywhere, just a typo.
      # TRAP: GBIF places diatoms in phylum Ochrophyta -- the SAME phylum as
      # the kelps (Phaeophyceae, in "macroalgae" above) -- so this MUST stay
      # a class-level rule. A phylum-level Ochrophyta rule in either
      # direction would be wrong: it would exclude the rockweeds or admit
      # the diatoms into the wrong group.
      list(
        group = "phytoplankton",
        when = list(
          list(phylum = c("Chlorophyta", "Prasinodermophyta")),
          list(class = c(
            "Stylonematophyceae", "Rhodellophyceae", "Klebsormidiophyceae",
            "Coleochaetophyceae", "Chlorokybophyceae", "Mesostigmatophyceae",
            "Zygnematophyceae", "Dinophyceae"
          )),
          list(class = "Bacillariophyceae") # 2026-09-13 fix
        )
      ),

      # Fishes. The original list ("Actinopteri", "Chondrichthyes", "Myxini")
      # matched almost nothing: GBIF's backbone carries NO class at all for
      # the ray-finned fishes (its Actinopterygii/Actinopteri node is not an
      # accepted backbone class) and names the cartilaginous fishes
      # "Elasmobranchii", not "Chondrichthyes". Fixed 2026-09-03 after
      # measuring 484,072 of 903,412 "macroinvertebrates" records (54%) were
      # fish. Tunicates (Ascidiacea), birds (Aves) and mammals (Mammalia) all
      # DO carry a class, so the class-less-Chordata fallback below cannot
      # swallow them.
      list(
        group = "fishes",
        when = list(
          list(class = c(
            "Actinopteri", "Actinopterygii", "Teleostei", "Chondrichthyes",
            "Elasmobranchii", "Holocephali", "Myxini", "Petromyzonti",
            "Cephalaspidomorphi", "Sarcopterygii", "Coelacanthi", "Dipneusti"
          )),
          list(phylum = "Chordata", class = NA_character_)
        )
      ),

      # Birds & mammals
      list(
        group = "birds_mammals",
        when = list(list(class = c("Aves", "Mammalia")))
      ),

      # Terrestrial arthropods
      list(
        group = "terrestrial_arthropods",
        when = list(list(class = c("Insecta", "Arachnida", "Collembola", "Chilopoda")))
      ),

      # Parasites (monogeneans, cestodes, trematodes, parasitic copepods, myxozoans)
      list(
        group = "parasites",
        when = list(
          list(class = c("Monogenea", "Cestoda", "Trematoda")),
          list(order = c(
            "Siphonostomatoida", "Poecilostomatoida", "Bivalvulida",
            "Multivalvulida", "Porocephalida", "Raillietiellida"
          ))
        )
      ),

      # Zooplankton. "Copepoda" added 2026-09-13 alongside the existing
      # "Hexanauplia" -- GBIF's current backbone calls this class
      # Hexanauplia, NCBI's calls it Copepoda, and both spellings appear in
      # real data, so both must map to the same group.
      list(
        group = "zooplankton",
        when = list(
          list(order = c("Euphausiacea", "Pteropoda")),
          list(class = c(
            "Hexanauplia", "Copepoda", "Appendicularia", "Hydrozoa",
            "Cubozoa", "Scyphozoa", "Branchiopoda", "Ostracoda"
          )),
          list(phylum = c("Ctenophora", "Chaetognatha")),
          # Alveolates (ciliates, dinoflagellates, apicomplexans)
          list(phylum = c("Ciliophora", "Protalveolata")),
          list(class = c("Intramacronucleata", "Postciliodesmatophora"))
        )
      ),

      # Apicomplexan parasites
      list(
        group = "parasites",
        when = list(
          list(phylum = "Apicomplexa"),
          list(class = "Perkinsea")
        )
      ),

      # Meiofauna
      list(
        group = "meiofauna",
        when = list(
          list(phylum = c(
            "Nematoda", "Tardigrada", "Gastrotricha", "Kinorhyncha",
            "Xenacoelomorpha", "Priapulida"
          )),
          list(class = "Eurotatoria")
        )
      )
    ),
    catch_all = "macroinvertebrates",
    kingdom_guard_vocabulary = c("Animalia", "Metazoa")
  )
}


# =============================================================================
# assign_sampling_group()
# =============================================================================

#' Assign Sampling Groups from Taxonomic Rank Columns
#'
#' Classifies each row of a taxonomy table into a \code{sampling_group}
#' (the shared-effort denominator, kernel-fit group, and dark-diversity-floor
#' group used throughout the TaxaID ecosystem) using an ordered,
#' first-match-wins rule scheme -- see \code{\link{default_sampling_scheme}}.
#' This is the single package-level home for logic that was previously an
#' inline \code{dplyr::case_when()} duplicated across five workflow files,
#' and had silently drifted three times before this fix (see
#' \code{\link{default_sampling_scheme}}'s Details).
#'
#' @param taxonomy A data frame (or tibble) with at least some of the columns
#'   named in \code{rank_cols}. Returned as-is with a new \code{sampling_group}
#'   column added.
#' @param scheme A sampling-group scheme object; see
#'   \code{\link{default_sampling_scheme}} for the required shape. Supply a
#'   custom scheme (e.g. \code{default_sampling_scheme()} with an appended or
#'   edited rule) to override the default classification -- the whole
#'   \code{rules}/\code{catch_all}/\code{kingdom_guard_vocabulary} object is
#'   used exactly as supplied, with no merging against the default.
#' @param rank_cols Character vector of taxonomic rank columns to read, in
#'   COARSE-TO-FINE order. Default \code{c("kingdom", "phylum", "class",
#'   "order")} -- the four ranks every rule in \code{default_sampling_scheme()}
#'   reads. A column absent from \code{taxonomy} is treated as entirely
#'   \code{NA} (never an error), so a taxonomy table missing e.g. \code{order}
#'   still classifies on the ranks it does have.
#' @param kingdom_guard Logical, default \code{TRUE}. When a row reaches the
#'   catch-all (\code{scheme$catch_all}, normally \code{"macroinvertebrates"})
#'   and its \code{kingdom} is NOT one of \code{scheme$kingdom_guard_vocabulary}
#'   (default \code{c("Animalia", "Metazoa")}), the row's \code{sampling_group}
#'   is set to \code{NA} instead of the catch-all. \strong{This is the single
#'   mechanism that closes the open-ended protist tail}: rather than
#'   enumerating every non-animal class GBIF's backbone might ever produce
#'   (Heliozoa, Amoebozoa, Ascomycota, Chytridiomycota, Foraminifera, ... --
#'   an unbounded and ever-growing list), any row whose kingdom is not
#'   plausibly an animal is refused the animal-flavoured catch-all
#'   ("macroinvertebrates" literally means "not a vertebrate ANIMAL") and
#'   surfaced as \code{NA} instead, where it is visible to a caller auditing
#'   unmatched rows rather than silently, indefinitely counted as a benthic
#'   invertebrate. The guard deliberately does NOT fire on a row with a
#'   \code{NA} (missing) kingdom -- a row with no usable taxonomy at all is a
#'   different problem (it may be genuinely novel), not something this
#'   function should silently discard. Set \code{kingdom_guard = FALSE} to
#'   restore the old case_when() behaviour, where every unmatched row (any
#'   kingdom, including \code{NA}) becomes the catch-all.
#' @param harmonise Logical, default \code{FALSE}. When \code{TRUE},
#'   \code{taxonomy} is harmonised to \code{scheme}'s backbone BEFORE
#'   classification, via \code{\link{verify_taxon_names}(backbone_id =
#'   backbone_id)} -> \code{\link{change_backbone}()} -- the same idiom
#'   \code{CaliforniaIntertidal/scope_classifier.R}'s
#'   \code{harmonize_ranks_to_gbif()} documents, and the one
#'   \code{PtConceptionWorkflow_18S_2_single_site.R} already uses to fold in
#'   an NCBI-backbone dataset. This lets an NCBI-backbone match object (e.g.
#'   one carrying \code{class = "Copepoda"}, \code{class =
#'   "Thalassiosirophyceae"}, or kingdom \code{"Chromista"}/\code{"Protozoa"}
#'   in vocabulary the default scheme does not otherwise recognise) be
#'   classified correctly against a GBIF-vocabulary scheme, at a real cost:
#'   \strong{one backbone name-verification lookup per unique value at the
#'   finest available rank in \code{rank_cols}} (so, typically, one call per
#'   unique \code{order} value -- cheap relative to a per-species lookup, but
#'   not free, and it is a live API call unless \code{cache_dir} serves it
#'   from a prior run). \code{harmonise} is OFF by default specifically
#'   because of this cost -- most callers already have GBIF-vocabulary
#'   taxonomy and gain nothing from paying it. A rank name that fails to
#'   resolve keeps its ORIGINAL value rather than becoming \code{NA} (matches
#'   the source and never silently loses taxonomy), and so does one the
#'   backbone resolves at the WRONG RANK -- see the \emph{Rank agreement}
#'   section, which is what stops a homonym at another rank from overwriting
#'   the row's whole lineage.
#' @param backbone_id Integer backbone ID passed to
#'   \code{\link{verify_taxon_names}} when \code{harmonise = TRUE}. Default
#'   \code{11L} (GBIF), matching \code{default_sampling_scheme()}'s own
#'   vocabulary. Ignored when \code{harmonise = FALSE}.
#' @param cache_dir Optional directory for a persistent, content-keyed cache
#'   of the harmonisation lookup (one \code{.rds} file, keyed on the sorted
#'   unique rank names actually resolved) -- only used, and only relevant,
#'   when \code{harmonise = TRUE}. \code{NULL} (default) does no caching, so
#'   every call re-resolves every unique name.
#' @param verbose Logical, default \code{TRUE}. Print one table of the
#'   resulting \code{sampling_group} counts (including the \code{NA} count)
#'   after classification, and progress messages during harmonisation.
#'
#' @return \code{taxonomy} (or its harmonised copy, when \code{harmonise =
#'   TRUE}) with a new \code{sampling_group} character column added.
#'   \code{NA} where no rule matched AND the kingdom guard fired; otherwise
#'   always one of the group names in \code{scheme$rules} or
#'   \code{scheme$catch_all}.
#'
#' @section Empty-string normalisation:
#' \code{""} is normalised to \code{NA} across every present \code{rank_cols}
#' column BEFORE classification. Real GBIF-derived taxonomy stores
#' "unclassified at this rank" as an empty string, not \code{NA} -- the same
#' real-data quirk \code{TaxaExpect::compute_adaptive_sampling_groups()} and
#' \code{TaxaAssign::join_priors()} already normalise this way. This is
#' behaviour-neutral for every \code{==}/\code{\%in\%} test in the scheme
#' (\code{""} and \code{NA} both fail them identically), but it is what lets
#' the class-less-Chordata fish clause be written honestly as "class is
#' missing" rather than as a fragile \code{class != ""} check.
#'
#' @section Backbone-mismatch detection (\code{harmonise = FALSE}):
#' When \code{harmonise = FALSE}, this function does two cheap, static checks
#' for signs the input taxonomy is NOT in the scheme's expected GBIF
#' vocabulary, and emits ONE warning (naming what it saw) if either fires:
#' (1) a \code{taxonomy_backbone} attribute on \code{taxonomy} that does not
#' look like GBIF/backbone 11; (2) presence of a class value GBIF's backbone
#' is confirmed NOT to carry --
#' \code{"Thalassiosirophyceae"}/\code{"Bigyra"}/\code{"Phytomastigophora"}
#' (per \code{scope_classifier.R}'s own verified BACKBONE TRAP comparison
#' table). \strong{\code{"Copepoda"} is deliberately NOT used as a mismatch
#' signal}, even though it is a genuinely NCBI-flavoured class name: this
#' function's own regression check against real GBIF-backbone occurrence
#' data (\code{PtCon18SSchulte_occurrences_clean.rds}) found \code{"Copepoda"}
#' live in real GBIF output too, not only in NCBI match objects -- so it is
#' handled directly in the zooplankton rule (see
#' \code{\link{default_sampling_scheme}}'s 2026-09-13 notes) rather than
#' treated as a mismatch symptom, which would have produced a false warning
#' on perfectly correct GBIF input. Silent misclassification from an
#' unnoticed backbone mismatch is the exact failure class this whole file
#' exists to end, so this check errs toward naming what it saw rather than
#' staying silent -- but it is a heuristic, not exhaustive, and passing
#' \code{harmonise = TRUE} (or verifying the input's backbone directly) is
#' the reliable fix, not a substitute for reading the warning.
#'
#' @section Rank agreement (\code{harmonise = TRUE}):
#' The harmoniser resolves each row's finest available rank NAME and then
#' overwrites \code{kingdom}/\code{phylum}/\code{class}/\code{order} from the
#' lineage the backbone returns. That is only safe if the backbone's answer is
#' about the SAME TAXON the probe column named, so a resolution is accepted
#' only when one of two things holds:
#' \enumerate{
#'   \item \code{\link{verify_taxon_names}}'s \code{matched_rank} equals the
#'     rank of the probe column. This is the ordinary case, and it is also what
#'     keeps SYNONYM resolution working -- an outdated spelling resolves to the
#'     backbone's accepted name, which is by definition not the name that was
#'     asked about, so only the rank can vouch for it.
#'   \item The rank differs, but the returned lineage carries the probe name
#'     ITSELF at the probe's own rank. That is a same-clade duplication rather
#'     than a homonym: GBIF holds a genus \emph{Spionidae} inside family
#'     Spionidae and a genus \emph{Arthropoda} inside phylum Arthropoda, so the
#'     terminal match is a genus while every rank above it is exactly the
#'     lineage the row already had.
#' }
#' A row failing both keeps its ORIGINAL taxonomy -- the same fallback an
#' unresolved name gets -- and is named in a warning.
#'
#' The case that forced this: GBIF's backbone contains a tachinid \strong{fly
#' genus} named \emph{Polychaeta}
#' (\code{Animalia|Arthropoda|Insecta|Diptera|Tachinidae|Polychaeta}, verified
#' live). Without the gate, a row whose \code{class} column reads
#' \code{"Polychaeta"} -- the annelid class, correct in NCBI -- was matched
#' against that genus and had its whole lineage overwritten
#' (\code{Annelida} -> \code{Arthropoda}, \code{Polychaeta} ->
#' \code{Insecta}, and a fabricated \code{order = "Diptera"}). On the
#' 2026-09-15 PtConception 18S run that hit 7 marine polychaete taxa across 17
#' rows, grouping every one of them as \code{terrestrial_arthropods} and --
#' because a downstream marine filter reads the harmonised phylum/class --
#' dropping them from the species list entirely, silently.
#'
#' \strong{And \emph{Polychaeta} was not alone.} Scanning every
#' (name, rank) pair in that run's NCBI-side taxonomy against GBIF -- 288
#' pairs -- found 15 rank disagreements. Rule 2 rescues 8 of them (the
#' \emph{Arthropoda} and polychaete-family duplications above). Of the 7 the
#' gate rejects, five are genuine cross-lineage homonyms that would each have
#' rewritten a whole lineage into an unrelated one:
#' \tabular{lll}{
#'   \strong{name} \tab \strong{column rank} \tab \strong{what GBIF matched} \cr
#'   Polychaeta \tab class \tab a tachinid fly genus (Insecta|Diptera) \cr
#'   Ctenophora \tab phylum \tab a crane-fly genus (Insecta|Diptera) \cr
#'   Ciliophora \tab phylum \tab a FUNGUS genus (Fungi|Ascomycota) \cr
#'   Appendicularia \tab class \tab a flowering-plant genus (Plantae|Myrtales) \cr
#'   Pilidiophora \tab class \tab a gregarine genus (Chromista|Myzozoa) \cr
#' }
#' Only \emph{Polychaeta}'s taxa happened to be noticed, because they were
#' dropped; a corrupted lineage that stays marine is silent. The remaining two
#' rejections, \code{"Bacillariophyta"} (NCBI phylum, GBIF class
#' \code{Bacillariophyceae}) and \code{"Bigyra"} (NCBI class, GBIF phylum), are
#' genuine NCBI-vs-GBIF rank-assignment differences for the same clade rather
#' than homonyms. Rejecting them is harmless: the row keeps its NCBI value, the
#' diatom rule here is class-level by design, and
#' \code{classify_18S_functional()} keys diatoms on the class
#' (\code{Bacillariophyceae}), never on that phylum value.
#'
#' A looser third rule -- accept a rank-mismatched match whose lineage contains
#' ANY of the row's original rank values -- was considered and rejected. It
#' rescues nothing rule 2 does not (NCBI gives diatoms no \code{kingdom} at
#' all, so a bare \code{"Bacillariophyta"} row has no other value to test), and
#' letting a \code{kingdom} match carry the test would re-admit
#' \emph{Polychaeta} for any caller whose input already says
#' \code{"Animalia"} rather than NCBI's \code{"Metazoa"}.
#'
#' \strong{Net effect on the real 18S run}: of the 97 unique names it resolves,
#' 90 agree on rank outright, 6 get no GBIF match (already handled by the
#' original-value fallback), and \emph{Polychaeta} is the single rejection --
#' recovering all 7 taxa and 17 rows as \code{macroinvertebrates}, all passing
#' the marine filter, with the phytoplankton, macroalgae and zooplankton counts
#' unchanged.
#'
#' Because a cache written before this gate existed carries no
#' \code{matched_rank} and so cannot be checked, such a cache is discarded and
#' re-resolved rather than trusted -- re-running with an old \code{cache_dir}
#' is exactly when a silent re-admission would be least likely to be noticed.
#'
#' @seealso \code{\link{default_sampling_scheme}}
#' @export
#'
#' @examples
#' tax <- data.frame(
#'   phylum = c("Chordata", "Chordata", "Ochrophyta", "Arthropoda"),
#'   class  = c(NA, "Aves", "Bacillariophyceae", "Copepoda"),
#'   order  = c(NA, NA, NA, NA)
#' )
#' assign_sampling_group(tax, verbose = FALSE)$sampling_group
assign_sampling_group <- function(taxonomy,
                                   scheme = default_sampling_scheme(),
                                   rank_cols = c("kingdom", "phylum", "class", "order"),
                                   kingdom_guard = TRUE,
                                   harmonise = FALSE,
                                   backbone_id = 11L,
                                   cache_dir = NULL,
                                   verbose = TRUE) {
  # --- Input validation -------------------------------------------------
  if (!is.data.frame(taxonomy)) {
    stop("assign_sampling_group: `taxonomy` must be a data frame.")
  }
  if (!is.list(scheme) || is.null(scheme$rules) || is.null(scheme$catch_all)) {
    stop("assign_sampling_group: `scheme` must be a sampling-group scheme ",
         "object (see default_sampling_scheme()) with `rules` and `catch_all`.")
  }
  if (!is.character(rank_cols) || length(rank_cols) == 0L) {
    stop("assign_sampling_group: `rank_cols` must be a non-empty character vector.")
  }
  if (!is.logical(kingdom_guard) || length(kingdom_guard) != 1L || is.na(kingdom_guard)) {
    stop("assign_sampling_group: `kingdom_guard` must be TRUE or FALSE.")
  }
  if (!is.logical(harmonise) || length(harmonise) != 1L || is.na(harmonise)) {
    stop("assign_sampling_group: `harmonise` must be TRUE or FALSE.")
  }

  # --- Empty strings first (see @section above) --------------------------
  present_ranks <- intersect(rank_cols, names(taxonomy))
  for (r in present_ranks) {
    taxonomy[[r]] <- dplyr::na_if(as.character(taxonomy[[r]]), "")
  }

  # --- Harmonise, or warn about a likely mismatch -------------------------
  if (harmonise) {
    taxonomy <- .harmonise_taxonomy_to_backbone(
      taxonomy, rank_cols = rank_cols, backbone_id = backbone_id,
      cache_dir = cache_dir, verbose = verbose
    )
  } else {
    .warn_possible_backbone_mismatch(taxonomy, rank_cols)
  }

  n <- nrow(taxonomy)
  group <- rep(NA_character_, n)
  matched <- rep(FALSE, n)

  # --- First-match-wins rule walk -----------------------------------------
  for (rule in scheme$rules) {
    remaining <- !matched
    if (!any(remaining)) break

    rule_mask <- rep(FALSE, n)
    for (clause in rule$when) {
      clause_mask <- rep(TRUE, n)
      for (rk in names(clause)) {
        val <- clause[[rk]]
        col <- if (rk %in% names(taxonomy)) taxonomy[[rk]] else rep(NA_character_, n)
        if (length(val) == 1L && is.na(val)) {
          m <- is.na(col)
        } else {
          m <- !is.na(col) & col %in% val
        }
        clause_mask <- clause_mask & m
      }
      rule_mask <- rule_mask | clause_mask
    }

    hit <- remaining & rule_mask
    if (any(hit)) {
      group[hit] <- rule$group
      matched[hit] <- TRUE
    }
  }

  # --- Catch-all -----------------------------------------------------------
  catch_all_hit <- !matched
  group[catch_all_hit] <- scheme$catch_all
  matched[catch_all_hit] <- TRUE

  # --- Kingdom guard ---------------------------------------------------------
  if (kingdom_guard) {
    animal_vocab <- scheme$kingdom_guard_vocabulary
    if (is.null(animal_vocab)) animal_vocab <- c("Animalia", "Metazoa")
    kingdom_col <- if ("kingdom" %in% names(taxonomy)) taxonomy[["kingdom"]] else rep(NA_character_, n)
    guard_hit <- catch_all_hit & !is.na(kingdom_col) & !(kingdom_col %in% animal_vocab)
    group[guard_hit] <- NA_character_
  }

  out <- taxonomy
  out$sampling_group <- group

  if (verbose) {
    cat("\nsampling_group counts:\n")
    print(table(out$sampling_group, useNA = "always"))
  }

  out
}


# =============================================================================
# Internal helpers
# =============================================================================

#' Warn once when the input taxonomy looks like it is not in GBIF vocabulary
#' @noRd
.warn_possible_backbone_mismatch <- function(taxonomy, rank_cols) {
  reasons <- character(0)

  bb <- attr(taxonomy, "taxonomy_backbone")
  if (!is.null(bb) && length(bb) == 1L && !is.na(bb) &&
      !grepl("gbif|backbone_11|^11$", as.character(bb), ignore.case = TRUE)) {
    reasons <- c(reasons, sprintf(
      "taxonomy_backbone attribute = \"%s\" (this scheme expects GBIF vocabulary)",
      bb
    ))
  }

  # Class values confirmed present in real NCBI match objects and confirmed
  # ABSENT from real GBIF occurrence data (scope_classifier.R's BACKBONE TRAP
  # table). Deliberately excludes "Copepoda" -- see roxygen above for why.
  ncbi_only_classes <- c("Thalassiosirophyceae", "Bigyra", "Phytomastigophora")
  present <- intersect(rank_cols, names(taxonomy))
  hits <- character(0)
  for (col in present) {
    vals <- unique(stats::na.omit(as.character(taxonomy[[col]])))
    hits <- union(hits, intersect(ncbi_only_classes, vals))
  }
  if (length(hits) > 0L) {
    reasons <- c(reasons, sprintf(
      "NCBI-only value(s) present: %s", paste(hits, collapse = ", ")
    ))
  }

  if (length(reasons) > 0L) {
    warning(
      "assign_sampling_group: possible taxonomy-backbone mismatch (",
      paste(reasons, collapse = "; "), "). default_sampling_scheme() is ",
      "written in GBIF-backbone vocabulary; classifying an NCBI-backbone ",
      "taxonomy against it can silently misclassify rows. Set harmonise = ",
      "TRUE to convert the input to the scheme's backbone first, or verify ",
      "the input's own backbone directly.",
      call. = FALSE
    )
  }
  invisible(NULL)
}

#' Harmonise a taxonomy table to a scheme's backbone before classification
#'
#' Resolves each row's finest available rank NAME (within `rank_cols`) via
#' verify_taxon_names()/change_backbone(), then overwrites kingdom/phylum/
#' class/order with the resolved values. Falls back to the row's original
#' values wherever nothing resolves, OR where the backbone resolved the name
#' at a rank other than the probe column's own rank (the homonym gate -- see
#' the "Rank agreement" roxygen section on assign_sampling_group()).
#' @noRd
.harmonise_taxonomy_to_backbone <- function(taxonomy, rank_cols, backbone_id,
                                             cache_dir, verbose) {
  present <- intersect(rank_cols, names(taxonomy))
  if (length(present) == 0L) {
    stop("assign_sampling_group: harmonise = TRUE requires at least one of ",
         "`rank_cols` to be present in `taxonomy`.")
  }

  norm <- function(x) {
    x <- as.character(x)
    x[!nzchar(trimws(x))] <- NA_character_
    x
  }

  # Finest-first cascade: rank_cols is coarse-to-fine, so reverse it.
  # probe_rank records WHICH column each probe name came from -- the rank the
  # backbone's answer must agree with (see .rank_agreement_mask()).
  cascade <- rev(present)
  n <- nrow(taxonomy)
  probe_name <- rep(NA_character_, n)
  probe_rank <- rep(NA_character_, n)
  for (r in cascade) {
    v <- norm(taxonomy[[r]])
    fill <- is.na(probe_name) & !is.na(v)
    probe_name[fill] <- v[fill]
    probe_rank[fill] <- r
  }

  need <- sort(unique(stats::na.omit(probe_name)))
  if (length(need) == 0L) {
    if (verbose) {
      message("assign_sampling_group: harmonise = TRUE but no resolvable ",
              "rank name found in `taxonomy`; nothing to harmonise.")
    }
    return(taxonomy)
  }

  cache_path <- NULL
  lookup <- NULL
  if (!is.null(cache_dir)) {
    if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)
    cache_path <- file.path(cache_dir, "sampling_group_harmonise_cache.rds")
    if (file.exists(cache_path)) {
      lookup <- readRDS(cache_path)
      # Caches written before the rank-agreement gate carry no matched_rank,
      # so their entries CANNOT be checked. Silently reusing one would let the
      # exact homonym this gate exists to stop (GBIF's fly genus "Polychaeta")
      # back in through the cache on the very re-runs the gate was added for.
      # Discard it -- re-resolving is one cheap API pass, a wrong lineage is
      # not.
      if (!"matched_rank" %in% names(lookup)) {
        if (verbose) {
          message("assign_sampling_group: harmonise cache predates the ",
                  "rank-agreement check (no matched_rank column) and cannot ",
                  "be verified; discarding it and re-resolving.")
        }
        lookup <- NULL
      } else {
        cached_n <- length(intersect(need, lookup$source_name))
        need <- setdiff(need, lookup$source_name)
        if (verbose) {
          message(sprintf(
            "assign_sampling_group: harmonise cache hit for %d name(s); %d to resolve.",
            cached_n, length(need)
          ))
        }
      }
    }
  }

  if (length(need) > 0L) {
    if (verbose) {
      message(sprintf(
        "assign_sampling_group: resolving %d unique name(s) against backbone %s...",
        length(need), backbone_id
      ))
    }
    verified <- verify_taxon_names(need, backbone_id = backbone_id)
    fresh <- change_backbone(
      verified,
      input_col = "user_supplied_name",
      old_backbone_label = "source_name",
      new_backbone_label = "resolved_name",
      keep_unmatched = TRUE
    )
    # matched_rank is the rank the backbone ACTUALLY resolved the name at, and
    # is taken from verify_taxon_names()'s own output rather than from
    # change_backbone()'s pass-through, so it survives regardless of what that
    # function chooses to keep. Without it the gate below cannot run.
    fresh$matched_rank <- if ("matched_rank" %in% names(verified)) {
      as.character(verified$matched_rank)[match(fresh$source_name,
                                                verified$user_supplied_name)]
    } else {
      NA_character_
    }
    # Keep every rank the cascade can probe at (not just the four the scheme
    # reads), because the gate below checks the returned lineage AT THE PROBE'S
    # OWN RANK and cannot do that for a rank it did not keep.
    keep_cols <- c("source_name", "matched_rank",
                   intersect(unique(c("kingdom", "phylum", "class", "order", rank_cols)),
                             names(fresh)))
    fresh <- fresh[, keep_cols, drop = FALSE]
    fresh <- fresh[!duplicated(fresh$source_name), , drop = FALSE]

    lookup <- if (is.null(lookup)) {
      fresh
    } else {
      # Take the columns the two frames share, on BOTH sides -- subsetting only
      # `lookup` leaves the frames with different widths whenever a later batch
      # resolves a rank the cached one never carried, and rbind() then errors.
      shared <- intersect(names(lookup), names(fresh))
      merged <- rbind(lookup[, shared, drop = FALSE], fresh[, shared, drop = FALSE])
      merged[!duplicated(merged$source_name), , drop = FALSE]
    }

    if (!is.null(cache_path)) {
      saveRDS(lookup, cache_path)
      if (verbose) {
        message(sprintf(
          "assign_sampling_group: harmonise cache now holds %d name(s) (%s).",
          nrow(lookup), basename(cache_path)
        ))
      }
    }
  }

  idx <- match(probe_name, lookup$source_name)

  # --- Rank-agreement gate ------------------------------------------------
  # Reject a resolution whose matched rank is not the rank of the column the
  # probe name came from. See the roxygen section of the same name for why
  # this is the whole check, and for the two real cases it was verified on.
  matched_rank <- if ("matched_rank" %in% names(lookup)) {
    tolower(trimws(as.character(lookup$matched_rank)[idx]))
  } else {
    rep(NA_character_, n)
  }
  resolved_at_all <- !is.na(idx) & !is.na(probe_name)

  # Rule 1: the backbone resolved the name at the probe column's own rank.
  # This is the ordinary case and the one that keeps SYNONYM resolution
  # working -- an outdated spelling resolves to the accepted name, which is
  # not the probe name, so only the rank can vouch for it.
  rank_agrees <- !is.na(matched_rank) & matched_rank == tolower(probe_rank)

  # Rule 2: the rank differs, but the returned lineage carries the probe name
  # ITSELF at the probe's own rank. That is a same-clade duplication, not a
  # homonym -- GBIF holds a genus Spionidae inside family Spionidae, and a
  # genus Arthropoda inside phylum Arthropoda, so the terminal match is a
  # genus while the lineage above it is exactly the one the row already had.
  # Verified on the real 18S export: this rescues 8 of the 15 rank
  # disagreements (Arthropoda + 7 polychaete family names) without admitting
  # a single cross-lineage homonym.
  lineage_at_probe_rank <- rep(NA_character_, n)
  for (r in unique(stats::na.omit(probe_rank))) {
    if (!r %in% names(lookup)) next
    at_r <- probe_rank == r & !is.na(probe_rank)
    lineage_at_probe_rank[at_r] <- as.character(lookup[[r]])[idx[at_r]]
  }
  lineage_agrees <- !is.na(lineage_at_probe_rank) &
    lineage_at_probe_rank == probe_name

  rank_disagrees <- resolved_at_all & !is.na(matched_rank) &
    !rank_agrees & !lineage_agrees

  if (any(rank_disagrees)) {
    bad <- unique(data.frame(
      name         = probe_name[rank_disagrees],
      column_rank  = probe_rank[rank_disagrees],
      matched_rank = matched_rank[rank_disagrees],
      stringsAsFactors = FALSE
    ))
    bad <- bad[order(bad$name), , drop = FALSE]
    warning(
      "assign_sampling_group: harmonise = TRUE rejected ", nrow(bad),
      " backbone match(es) resolved at the wrong rank (",
      sum(rank_disagrees), " row(s)); these rows keep their ORIGINAL ",
      "taxonomy: ",
      paste(sprintf("%s (%s column, backbone matched a %s)",
                    bad$name, bad$column_rank, bad$matched_rank),
            collapse = "; "),
      ". A name that resolves at a different rank is usually a homonym in a ",
      "different lineage (e.g. GBIF's backbone holds a FLY GENUS named ",
      "\"Polychaeta\"), and accepting it would overwrite the whole row's ",
      "lineage with that other taxon's.",
      call. = FALSE
    )
  }
  # Drop the rejected matches the same way an unresolved name is dropped: the
  # coalesce() below then falls back to the row's original values.
  idx[rank_disagrees] <- NA_integer_

  out <- taxonomy
  for (r in c("kingdom", "phylum", "class", "order")) {
    if (r %in% names(lookup)) {
      resolved <- lookup[[r]][idx]
      orig <- if (r %in% names(taxonomy)) norm(taxonomy[[r]]) else rep(NA_character_, n)
      out[[r]] <- dplyr::coalesce(resolved, orig)
    }
  }
  out
}
