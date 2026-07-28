#' @keywords internal
"_PACKAGE"

#' TaxaMatch: Store and Standardize Biological Match Data
#'
#' Ingests raw match data from external tools (BLAST, image classifiers,
#' acoustic recognizers) and produces a canonical match object for input to
#' TaxaLikely. Provides remote/local BLAST search and sequence filtering,
#' standardizes taxonomy across reference backbones, and offers per-sample
#' taxonomic consistency checks.
#'
#' @section Workflow:
#' The typical call order for a sequence/BLAST pipeline:
#' \enumerate{
#'   \item \code{\link{read_sequence_table}()} -- ingest DADA2, FASTA, or
#'     DNAStringSet
#'   \item \code{\link{filter_sequences}()} -- filter by length and abundance
#'   \item \code{\link{blast_sequences}()} -- remote NCBI or local BLAST search
#'   \item \code{\link{standardize_match_data}()} -- canonical column names
#'   \item \code{\link{filter_redundant_hypotheses}()} -- drop superseded ranks
#'   \item \code{\link{report_match}()} -- generate Methods/Results text
#' }
#' Image and acoustic pathways skip steps 1-3, calling one of
#' \code{\link{score_image_inat}()}, \code{\link{read_animl_output}()},
#' \code{\link{read_inaturalist_cv_output}()},
#' \code{\link{read_speciesnet_output}()}, or
#' \code{\link{read_birdnet_output}()} directly, then proceeding from step 4.
#'
#' @section Sequence input:
#' \describe{
#'   \item{\code{\link{read_sequence_table}}}{Ingest DADA2, FASTA, or
#'     DNAStringSet}
#'   \item{\code{\link{filter_sequences}}}{Filter by length and abundance}
#' }
#'
#' @section BLAST search:
#' \describe{
#'   \item{\code{\link{blast_sequences}}}{Remote NCBI or local BLAST search}
#' }
#'
#' @section Image input:
#' \describe{
#'   \item{\code{\link{score_image_inat}}}{Submit image(s) directly to the
#'     live iNaturalist CV API}
#'   \item{\code{\link{read_animl_output}}}{Ingest Animl (MegaDetector +
#'     SpeciesNet) camera trap CSV results}
#'   \item{\code{\link{read_inaturalist_cv_output}}}{Ingest saved
#'     iNaturalist CV API JSON responses}
#'   \item{\code{\link{read_speciesnet_output}}}{Ingest real SpeciesNet CLI
#'     (\code{google/cameratrapai}) batch prediction JSON}
#' }
#'
#' @section Acoustic input:
#' \describe{
#'   \item{\code{\link{read_birdnet_output}}}{Ingest BirdNET-Analyzer
#'     detection CSV results}
#' }
#'
#' @section Standardization:
#' \describe{
#'   \item{\code{\link{standardize_match_data}}}{Canonical column names}
#'   \item{\code{\link{filter_redundant_hypotheses}}}{Drop superseded ranks}
#'   \item{\code{\link{convert_taxonomy_backbone}}}{Remap rank columns to a
#'     target backbone (e.g. NCBI -> GBIF); adds \code{taxonomy_backbone} and
#'     \code{taxonomy_collision} diagnostic columns}
#'   \item{\code{\link{add_lowest_consistent_rank}}}{Per-observation: the
#'     finest rank at which all (or a majority of) candidate rows agree}
#' }
#'
#' @section Reporting:
#' \describe{
#'   \item{\code{\link{report_match}}}{Generate Methods/Results section}
#' }
#'
#' @references
#' Altschul SF, Gish W, Miller W, Myers EW, Lipman DJ (1990). Basic local
#' alignment search tool. Journal of Molecular Biology, 215(3), 403-410.
#' (NCBI BLAST, \code{\link{blast_sequences}})
#'
#' Kahl S, Wood CM, Eibl M, Klinck H (2021). BirdNET: A deep learning
#' solution for avian diversity monitoring. Ecological Informatics, 61,
#' 101236. (\code{\link{read_birdnet_output}})
#'
#' Beery S, Morris D, Yang S (2019). Efficient pipeline for camera trap image
#' review. arXiv:1907.06772. (MegaDetector, consumed by
#' \code{\link{read_animl_output}})
#'
#' iNaturalist Computer Vision API and SpeciesNet:
#' see \code{\link{score_image_inat}}, \code{\link{read_inaturalist_cv_output}},
#' and \code{\link{read_speciesnet_output}} for the specific
#' endpoints/formats each function targets.
#'
#' @seealso The TaxaID ecosystem's downstream consumer of this package's
#'   output is TaxaLikely, which converts match scores to likelihoods.
#'
#' @name TaxaMatch-package
#' @aliases TaxaMatch
NULL
