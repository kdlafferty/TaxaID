#' Default NCBI Nucleotide Length Ranges by Barcode Type
#'
#' A named list mapping lowercase barcode marker names to integer vectors
#' `c(min_bp, max_bp)`.  Keys are matched by prefix or substring (case
#' insensitive) so `"MiFishU"` matches `"mifish"`.  Length ranges are
#' intentionally generous to accommodate primer variation and partial
#' sequences.
#'
#' @format A named list of length 12.  Each element is an integer vector of
#'   length 2 (`c(min, max)`).
#'
#' @references
#' Miya et al. (2015) for MiFish/12S; Ward et al. (2005) for COI;
#' CBOL Plant Working Group (2009) for rbcL/matK; Taberlet et al. (2007)
#' for trnL; Schoch et al. (2012) for ITS/ITS2.
#'
#' @examples
#' barcode_length_defaults[["coi"]]
#' # 300 900
#'
#' @export
barcode_length_defaults <- list(
  "mifish" = c(130L, 210L), # MiFishU/E 12S amplicon 163-185 bp; bounds exclude non-target cross-amplicons
  "teleo"  = c(50L, 300L), # Teleo 12S amplicon ~60-100 bp
  "12s"    = c(100L, 600L), # General 12S vertebrate
  "16s"    = c(100L, 700L), # 16S vertebrate ~200-450 bp
  "coi"    = c(300L, 900L), # COI Folmer ~650 bp; mini ~130-200 bp
  "cytb"   = c(200L, 900L), # CytB partial ~300-700 bp
  "its2"   = c(100L, 600L), # ITS2 ~200-350 bp
  "its"    = c(100L, 900L), # ITS full ~500-750 bp
  "rbcl"   = c(400L, 800L), # rbcL ~550-650 bp
  "matk"   = c(600L, 1100L), # matK ~800-900 bp
  "18s"    = c(100L, 2000L), # 18S varies by primer set
  "trnl"   = c(10L, 300L) # trnL P6 loop ~10-150 bp
)


#' Resolve Barcode Length Bounds from a Barcode Term
#'
#' Looks up `barcode_term` in [barcode_length_defaults] and returns
#' `c(min_bp, max_bp)`.
#'
#' For vector input (multiple marker names), collects all matched ranges and
#' returns `c(min(mins), max(maxes))` so the query covers all supplied terms.
#' User-supplied `min_len` / `max_len` override the resolved bounds.
#'
#' @param barcode_term Character vector of barcode marker names (e.g.
#'   `"MiFishU"`, `"COI"`, `c("12S", "16S")`).
#' @param min_len,max_len Optional integer overrides.  When non-`NULL`,
#'   replace the auto-detected bound.
#'
#' @return Integer vector of length 2: `c(min_bp, max_bp)`.
#'
#' @examples
#' resolve_barcode_lengths("MiFishU")
#' # 130 210
#' resolve_barcode_lengths(c("12S", "16S"))
#' # 100 700  (union of both ranges)
#' resolve_barcode_lengths("COI", min_len = 500)
#' # 500 900  (min_len overrides auto-detected)
#'
#' @export
resolve_barcode_lengths <- function(barcode_term, min_len = NULL,
                                    max_len = NULL) {
  if (!is.null(min_len) && !is.null(max_len)) {
    min_i <- as.integer(min_len)
    max_i <- as.integer(max_len)
    if (min_i > max_i) {
      stop(sprintf(
        "resolve_barcode_lengths: min_len (%d) is greater than max_len (%d).",
        min_i, max_i
      ), call. = FALSE)
    }
    return(stats::setNames(c(min_i, max_i), c("min_bp", "max_bp")))
  }

  if (is.null(barcode_term)) {
    stop("Specify barcode_term for auto-detection, or provide both min_len and max_len")
  }

  all_ranges <- lapply(barcode_term, function(bt) {
    key <- tolower(trimws(bt))
    for (nm in names(barcode_length_defaults)) {
      if (startsWith(key, nm) || grepl(nm, key, fixed = TRUE)) {
        return(barcode_length_defaults[[nm]])
      }
    }
    NULL
  })

  matched <- Filter(Negate(is.null), all_ranges)

  if (length(matched) == 0L) {
    resolved <- c(100L, 2000L)
    if (is.null(min_len) || is.null(max_len)) {
      message(sprintf(
        "No length defaults found for barcode_term '%s'. Using fallback 100-2000 bp. ",
        paste(barcode_term, collapse = "/")
      ), "Supply min_len/max_len to override.")
    }
  } else {
    all_mins <- vapply(matched, `[`, integer(1L), 1L)
    all_maxes <- vapply(matched, `[`, integer(1L), 2L)
    resolved <- c(min(all_mins), max(all_maxes))
  }

  if (!is.null(min_len)) resolved[1L] <- as.integer(min_len)
  if (!is.null(max_len)) resolved[2L] <- as.integer(max_len)

  stats::setNames(resolved, c("min_bp", "max_bp"))
}


#' Default PCR Primer Sequences by Barcode/Primer-Set Name
#'
#' A named list mapping specific primer-set names to their forward/reverse
#' primer sequences (5' to 3', IUPAC-degenerate characters allowed). Unlike
#' [barcode_length_defaults], which merges related primer variants under one
#' generic marker key (e.g. `"mifish"` covers both MiFish-U and MiFish-E,
#' since their amplicon lengths overlap), this registry requires the *exact*
#' primer variant because different variants of the same marker can have
#' genuinely different primer sequences. There is deliberately no generic
#' `"mifish"` entry here — see [resolve_barcode_primers()].
#'
#' Populated incrementally and only for primer sets that have been directly
#' verified against their primary publication. A marker or primer set not yet
#' listed here does not mean it lacks a standard primer pair -- it means no
#' one has yet verified and added it. Supply `primer_fwd`/`primer_rev`
#' directly to any function using this registry (e.g.
#' [TaxaLikely::trim_to_amplicon()]) for any primer set not listed here, or
#' pre-trim sequences to the amplicon region with the external CRABS tool
#' before use (see `TaxaLikely::read_crabs_output()`).
#'
#' @format A named list. Each element is a list with `fwd`, `rev` (character,
#'   5'-3', IUPAC-degenerate bases allowed) and `amplicon_range` (integer
#'   vector `c(min_bp, max_bp)` as reported in the source publication -- note
#'   this may differ from the wider, deliberately generous bounds in
#'   [barcode_length_defaults]).
#'
#' @section Verification method:
#' Every entry here was checked two ways before being added: (1) cross-checked
#' against at least two independent sources reproducing the primer verbatim
#' (ideally including the primary publication itself), and (2) empirically
#' tested with [Biostrings::matchPattern()] against a real GenBank reference
#' sequence for the relevant genome (a real mitogenome for mitochondrial
#' markers, a real chloroplast genome for plastid markers) to confirm the
#' pair actually locates a plausible amplicon and to resolve any
#' forward/reverse ambiguity empirically rather than by trusting a table's
#' own labels. This caught two real errors that verbatim cross-checking alone
#' would have missed: a wrong amplicon length reported for `cytb-kocher` by
#' two secondary sources (see that entry's own note below), and a genuine
#' forward/reverse mislabeling for `matk-kim` in one otherwise-authoritative
#' primer table (the Canadian Centre for DNA Barcoding's own protocol PDF).
#'
#' @section Known limitations (read before trusting a result on real data):
#' \describe{
#'   \item{`coi-folmer` -- vertebrate mismatches}{Documented, empirically
#'     re-confirmed here: at a typical `max_mismatch_rate` (~0.12-0.15) this
#'     pair does not match human COI, and per the literature that motivated
#'     the 2013 Geller redesign, many other vertebrates as well. Designed
#'     and validated by its own authors for invertebrates only. For
#'     vertebrate COI, raise `max_mismatch_rate`, use a vertebrate-specific
#'     COI primer pair (not in this registry), or pre-trim with CRABS.}
#'   \item{`coi-leray` -- reduced species-level discriminatory power}{A real,
#'     bounded cost of using a shorter fragment: one direct comparison found
#'     a 313bp fragment resolved 95% of species via barcode-gap analysis
#'     versus 87% for a much shorter (55bp) mini-barcode. Expect somewhat
#'     worse resolution of very recently diverged sister species or cryptic
#'     complexes than `coi-folmer`'s full-length product would give -- not
#'     independently re-verified against a primary source here, background
#'     literature context only.}
#'   \item{`coi-leray` -- primer-binding-site mismatches in specific taxa}{A
#'     separate, mechanistically distinct problem from the above: real
#'     sequence variation at the `mlCOIintF` binding site causes outright
#'     non-amplification in some marine zooplankton lineages (Appendicularia;
#'     some *Oithona similis* populations show up to 6 mismatches). This is a
#'     property of this specific primer choice, not of fragment length --
#'     the more-degenerate "Leray-XT" variant partially mitigates it but is
#'     not implemented in this registry.}
#'   \item{`rbcla` -- amplicon length discrepancy}{The empirically-measured
#'     599bp (real *Arabidopsis* chloroplast DNA) does not match the
#'     "~670bp rbcLa barcode" figure commonly quoted elsewhere -- that figure
#'     likely describes a longer product using the alternative
#'     `rbcLajf634R` reverse primer (Fazekas et al. 2008), which is not
#'     implemented here. Not a defect in the entry, just a note that "rbcLa"
#'     as a term is used loosely across sources for more than one product
#'     length.}
#'   \item{No entry for the Geller et al. (2013) `jgLCO1490`/`jgHCO2198`
#'     redesign, or for pairing `mlCOIintF` with `jgHCO2198`}{Both primers
#'     encode several positions with inosine (dITP), a base analog with no
#'     representation in `Biostrings::DNAString`'s IUPAC alphabet. `coi-leray`
#'     uses Meyer (2003)'s inosine-free `dgHCO2198` instead, which binds the
#'     same site and is a real published alternative to `jgHCO2198`, not an
#'     approximation of it -- see that entry's own reference note.}
#'   \item{No entries for 18S, ITS, or ITS2}{Deliberately unpopulated, not an
#'     oversight: unlike every marker actually implemented here, none of
#'     these three has one single canonical primer pair to verify -- real
#'     studies use substantially different primer sets depending on the
#'     targeted variable region (e.g. 18S V4 vs V9) or organism group.
#'     Supply `primer_fwd`/`primer_rev` directly (from your own protocol) to
#'     any function using this registry, or pre-trim with CRABS.}
#' }
#'
#' @references
#' Miya M, Sato Y, Fukunaga T, Sado T, Poulsen JY, Sato K, Minamoto T,
#' Yamamoto S, Yamanaka H, Araki H, Kondoh M, Iwasaki W (2015). MiFish, a set
#' of universal PCR primers for metabarcoding environmental DNA from fishes:
#' detection of more than 230 subtropical marine species. Royal Society Open
#' Science 2: 150088. Primer sequences (Tables 2-3) independently
#' cross-checked against three secondary sources reproducing the same
#' primers verbatim before being entered here.
#'
#' Palumbi SR (1996). Nucleic acids II: the polymerase chain reaction. In:
#' Molecular Systematics, 2nd ed. (Hillis DM, Moritz C, Mable BK, eds),
#' pp 205-247. 16Sar-L/16Sbr-H primer sequences cross-checked against three
#' independent secondary sources and empirically confirmed (590bp amplicon)
#' against the real human mitogenome (GenBank NC_012920.1).
#'
#' Folmer O, Black M, Hoeh W, Lutz R, Vrijenhoek R (1994). DNA primers for
#' amplification of mitochondrial cytochrome c oxidase subunit I from
#' diverse metazoan invertebrates. Molecular Marine Biology and
#' Biotechnology 3(5): 294-299. LCO1490/HCO2198 sequences read directly from
#' this primary source (a scanned copy) and empirically confirmed against
#' the real *Drosophila melanogaster* mitogenome (GenBank NC_001709.1) --
#' the match landed at positions 1490-2198 exactly, matching the primers'
#' own position-based names, with a 709bp amplicon matching the paper's own
#' reported 710bp product. Known limitation, confirmed empirically here: at
#' `max_mismatch_rate` around 0.12-0.15, this primer pair does NOT match
#' human (or, per the literature that motivated the 2013 Geller redesign,
#' many other vertebrate) COI sequences -- consistent with the original
#' paper's own invertebrate-only design scope. Use a higher
#' `max_mismatch_rate`, a vertebrate-specific COI primer pair, or CRABS
#' pre-trimming for vertebrate COI data.
#'
#' Leray M, Yang JY, Meyer CP, Mills SC, Agudelo N, Ranwez V, Boehm JT,
#' Machida RJ (2013). A new versatile primer set targeting a short fragment
#' of the mitochondrial COI region for metabarcoding metazoan diversity:
#' application for characterizing coral reef fish gut contents. Frontiers in
#' Zoology 10: 34 (mlCOIintF -- fully IUPAC-standard, no inosine). Meyer CP
#' (2003) (unpublished redesign of the Folmer primers; dgHCO2198 -- also
#' fully IUPAC-standard). This specific pairing (mlCOIintF forward with
#' Meyer's dgHCO2198 reverse, rather than Geller et al. 2013's jgHCO2198) is
#' a real, published combination (e.g. Gomez-Rodriguez et al., "Biases in
#' bulk", Molecular Ecology 2020) -- chosen deliberately over jgHCO2198,
#' which encodes several positions with inosine (dITP), a base analog with
#' no representation in `Biostrings::DNAString`'s IUPAC alphabet.
#' `dgHCO2198` cross-checked against two independent sources. Empirically
#' confirmed against the real *Drosophila melanogaster* mitogenome
#' (NC_001709.1): unique hit at positions 1834-2198, a 365bp full PCR
#' product -- 365 minus both primers' combined length (52bp) is exactly
#' 313bp, reconciling this measurement with the "313bp Leray fragment"
#' figure ubiquitous in the metabarcoding literature, which refers to the
#' primer-excluded interior, not the primer-inclusive product this registry
#' reports (consistent with how `coi-folmer`'s 710bp is also
#' primer-inclusive). **Known limitations, from the literature (not
#' independently re-verified here):** shorter fragments carry fewer
#' phylogenetically informative sites than the full Folmer barcode, and
#' resolve species less reliably as a result -- one direct comparison found
#' a 313bp fragment resolved 95% of species via barcode-gap analysis versus
#' 87% for a much shorter (55bp) mini-barcode, i.e. a real but bounded cost,
#' not a fragment this short being unusable. Separately (a mismatch problem,
#' not a resolving-power problem), real primer-binding-site variation causes
#' outright non-amplification in specific marine zooplankton lineages
#' (Appendicularia; some *Oithona similis* populations show up to 6
#' mismatches to `mlCOIintF`) -- a caveat about this specific primer choice,
#' not a general property of using a shorter fragment.
#'
#' Kocher TD, Thomas WK, Meyer A, Edwards SV, Paabo S, Villablanca FX, Wilson
#' AC (1989). Dynamics of mitochondrial DNA evolution in animals:
#' amplification and sequencing with conserved primers. Proceedings of the
#' National Academy of Sciences USA 86(16): 6196-6200. L14841/H15149 core
#' annealing sequences (restriction-site cloning tails reported by some
#' secondary sources, e.g. a 5' `AAAAAGCTT`/`AAACTGCAG`, excluded -- they are
#' not part of the genomic template and would never match a real sequence).
#' Empirically confirmed (358bp) against the real human mitogenome
#' (NC_012920.1) -- this corrects a 309bp figure repeated verbatim by two
#' secondary sources (apparently propagated from a shared error), which the
#' direct empirical test disagreed with; a third secondary source's 359bp
#' figure was essentially confirmed (within 1bp, likely a fencepost
#' convention difference).
#'
#' Levin RA, Wagner WL, Hoch PC, et al. (2003). Family-level relationships of
#' Onagraceae based on chloroplast rbcL and ndhF data. American Journal of
#' Botany 90: 107-115 (rbcLa-F). Kress WJ, Erickson DL (2007). A two-locus
#' global DNA barcode for land plants. PLoS ONE 2(6): e508 (rbcLa-R).
#' Sequences cross-checked against the Canadian Centre for DNA Barcoding's
#' own "Primer Sets for Plants and Fungi" protocol PDF and two further
#' independent sources, and empirically confirmed (599bp) against the real
#' *Arabidopsis thaliana* chloroplast genome (NC_000932.1). Note: the
#' commonly-cited "~670bp rbcLa barcode" figure elsewhere in the literature
#' was NOT reproduced by this specific fwd/rev pair on real data -- it likely
#' refers to a longer product using the alternative `rbcLajf634R` reverse
#' primer (Fazekas et al. 2008), which is not implemented here.
#'
#' Hollingsworth PM et al. (CBOL Plant Working Group) (2009). A DNA barcode
#' for land plants. Proceedings of the National Academy of Sciences USA
#' 106(31): 12794-12797 (matK-3F_KIM/matK-1R_KIM, attributed to K-J Kim,
#' pers. comm.). The forward/reverse assignment conflicts between sources
#' consulted here -- most describe 3F_KIM as forward and 1R_KIM as reverse,
#' but the Canadian Centre for DNA Barcoding's own protocol PDF labels them
#' the other way around. Resolved empirically rather than guessed: tested
#' both orientations with `Biostrings::matchPattern()` against the real
#' *Arabidopsis thaliana* chloroplast genome (NC_000932.1) -- `3F_KIM`
#' matched directly upstream (true forward) and `1R_KIM`'s reverse
#' complement matched downstream (true reverse), a 874bp amplicon consistent
#' with this pair's commonly-cited ~850bp product size.
#'
#' Taberlet P, Coissac E, Pompanon F, Gielly L, Miquel C, Valentini A,
#' Vermat T, Corthier G, Brochmann C, Willerslev E (2007). Power and
#' limitations of the chloroplast trnL (UAA) intron for plant DNA barcoding.
#' Nucleic Acids Research 35(3): e14. Primer `g`/`h` sequences read directly
#' from this primary source's own Table 1, and empirically confirmed (87bp)
#' against the real *Arabidopsis thaliana* chloroplast genome (NC_000932.1)
#' -- within the paper's own documented P6-loop range of 10-143bp across
#' land plants (highly length-variable by design; this is the marker's
#' intended discriminatory signal, not primer-matching noise).
#'
#' @examples
#' barcode_primer_defaults[["mifish-u"]]
#'
#' @export
barcode_primer_defaults <- list(
  "mifish-u" = list(
    fwd = "GTCGGTAAAACTCGTGCCAGC",
    rev = "CATAGTGGGGTATCTAATCCCAGTTTG",
    amplicon_range = c(163L, 185L)
  ),
  "mifish-e" = list(
    fwd = "GTTGGTAAATCTCGTGCCAGC",
    rev = "CATAGTGGGGTATCTAATCCTAGTTTG",
    amplicon_range = c(170L, 185L)
  ),
  "16s-palumbi" = list(
    fwd = "CGCCTGTTTATCAAAAACAT",
    rev = "CCGGTCTGAACTCAGATCACGT",
    amplicon_range = c(500L, 590L)
  ),
  "coi-folmer" = list(
    fwd = "GGTCAACAAATCATAAAGATATTGG",
    rev = "TAAACTTCAGGGTGACCAAAAAATCA",
    amplicon_range = c(700L, 710L)
  ),
  "coi-leray" = list(
    fwd = "GGWACWGGWTGAACWGTWTAYCCYCC",
    rev = "TAAACTTCAGGGTGACCAAARAAYCA",
    amplicon_range = c(350L, 370L)
  ),
  "cytb-kocher" = list(
    fwd = "CCATCCAACATCTCAGCATGATGAAA",
    rev = "CCCCTCAGAATGATATTTGTCCTCA",
    amplicon_range = c(340L, 370L)
  ),
  "rbcla" = list(
    fwd = "ATGTCACCACAAACAGAGACTAAAGC",
    rev = "GTAAAATCAAGTCCACCRCG",
    amplicon_range = c(560L, 650L)
  ),
  "matk-kim" = list(
    fwd = "CGTACAGTACTTTTGTGTTTACGAG",
    rev = "ACCCAGTCCATCTGGAAATCTTGGTTC",
    amplicon_range = c(820L, 900L)
  ),
  "trnl-taberlet" = list(
    fwd = "GGGCAATCCTGAGCCAA",
    rev = "CCATTGAGTCTCTGCACCTATC",
    amplicon_range = c(49L, 182L)
  )
)


#' Resolve Primer Sequences from a Barcode/Primer-Set Term
#'
#' Looks up `barcode_term` in [barcode_primer_defaults]. Unlike
#' [resolve_barcode_lengths()], matching requires the *specific* primer
#' variant (e.g. `"MiFishU"`, not bare `"MiFish"`) because different variants
#' of what is loosely called "the same marker" can have genuinely different
#' primer sequences -- silently picking one would be a real correctness risk,
#' not a convenience shortcut. An ambiguous or unlisted term errors with
#' guidance rather than guessing.
#'
#' @param barcode_term Character scalar naming a specific primer set (e.g.
#'   `"MiFishU"`, `"mifish-e"`). Matching is case-insensitive and ignores
#'   `-`/`_`/space separators.
#'
#' @return A list with `fwd`, `rev` (character, 5'-3') and `amplicon_range`
#'   (integer `c(min_bp, max_bp)`).
#'
#' @examples
#' resolve_barcode_primers("MiFishU")
#' resolve_barcode_primers("mifish-e")
#'
#' @export
resolve_barcode_primers <- function(barcode_term) {
  if (is.null(barcode_term) || length(barcode_term) != 1L || is.na(barcode_term) ||
    !nzchar(trimws(barcode_term))) {
    stop("resolve_barcode_primers: barcode_term must be a single non-empty string")
  }

  norm <- function(x) gsub("[-_ ]", "", tolower(trimws(x)))
  key <- norm(barcode_term)
  reg_keys <- names(barcode_primer_defaults)
  reg_norm <- norm(reg_keys)

  exact <- which(reg_norm == key)
  if (length(exact) == 1L) {
    return(barcode_primer_defaults[[reg_keys[exact]]])
  }

  prefix <- which(startsWith(reg_norm, key))
  if (length(prefix) == 1L) {
    return(barcode_primer_defaults[[reg_keys[prefix]]])
  }

  if (length(prefix) > 1L) {
    stop(sprintf(
      paste0(
        "resolve_barcode_primers: '%s' is ambiguous -- matches %s. Specify the ",
        "exact primer variant (e.g. '%s'), or supply primer_fwd/primer_rev directly."
      ),
      barcode_term, paste0("'", reg_keys[prefix], "'", collapse = ", "), reg_keys[prefix[1]]
    ), call. = FALSE)
  }

  stop(sprintf(
    paste0(
      "resolve_barcode_primers: no primer defaults found for '%s'. Currently registered: %s. ",
      "Supply primer_fwd/primer_rev directly, or pre-trim with the external CRABS tool ",
      "(see TaxaLikely::read_crabs_output())."
    ),
    barcode_term, paste0("'", reg_keys, "'", collapse = ", ")
  ), call. = FALSE)
}


#' Resolve a Primer-Variant Barcode Term to the Marker It Amplifies
#'
#' A registered primer-variant name (see [barcode_primer_defaults]) --
#' `"COI-Folmer"`, `"16S-Palumbi"`, `"rbcLa"` -- is the correct term for
#' resolving primers and amplicon lengths, but it is **not** a term any
#' sequence database indexes: no GenBank record is tagged "Folmer". A search
#' query built from the variant name matches nothing, and because "nothing
#' found" is a legitimate outcome of a search, that failure is silent --
#' it looks like the taxon has no barcode rather than like a bad query.
#'
#' This maps such a term to the marker it amplifies, so a search can be built
#' from the marker while primer/length resolution keeps using the variant.
#' Any term that is not a recognised variant is returned unchanged, so a
#' custom or unregistered term still searches as itself.
#'
#' MiFish terms are deliberately **not** remapped: unlike the others, real
#' records are annotated with the MiFish primer name, so the variant is
#' genuinely searchable and callers already OR it together with `12S`.
#'
#' @param barcode_term Character vector of barcode/marker/primer-variant names.
#' @return Character vector the same length as `barcode_term`: the base marker
#'   name for a recognised primer variant, otherwise the input unchanged.
#' @examples
#' resolve_barcode_marker("COI-Folmer") # "COI"
#' resolve_barcode_marker("16S-Palumbi") # "16S"
#' resolve_barcode_marker("12S") # "12S" (unchanged)
#' resolve_barcode_marker("MiFishU") # "MiFishU" (deliberately unchanged)
#' @export
resolve_barcode_marker <- function(barcode_term) {
  if (is.null(barcode_term)) {
    return(barcode_term)
  }
  if (!is.character(barcode_term)) {
    stop("resolve_barcode_marker: barcode_term must be a character vector.",
      call. = FALSE
    )
  }

  variant_to_marker <- c(
    "coi-folmer"    = "COI",
    "coi-leray"     = "COI",
    "16s-palumbi"   = "16S",
    "cytb-kocher"   = "cytb",
    "rbcla"         = "rbcL",
    "matk-kim"      = "matK",
    "trnl-taberlet" = "trnL"
  )

  vapply(barcode_term, function(bt) {
    if (is.na(bt)) {
      return(NA_character_)
    }
    hit <- variant_to_marker[tolower(trimws(bt))]
    if (is.na(hit)) bt else unname(hit)
  }, character(1L), USE.NAMES = FALSE)
}
