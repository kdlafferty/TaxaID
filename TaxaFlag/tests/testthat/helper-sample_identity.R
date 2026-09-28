# Synthetic study: two markers, three runs each, five field samples per run.
# Blanks: CLEAN (lab taxa only) on R1, MISLABEL (carries the field community)
# on R2, PLANKTON (a rich community disjoint from the field) on R3.
.sig_fixture <- function(seed = 1, fail_run = NULL) {
  set.seed(seed)
  field_pool <- paste0("f", 1:80)
  plankton_pool <- paste0("p", 1:80)
  lab <- c("lab_human", "lab_fungus")
  rows <- list()
  add <- function(sample, marker, run, feats, depth) {
    w <- stats::rlnorm(length(feats), 0, 1)
    rows[[length(rows) + 1L]] <<- data.frame(
      sample_id = sample, marker = marker, run = run,
      event_id = paste0(sample, ".1"), taxon_name = paste(marker, feats, sep = "_"),
      species = feats, count = pmax(1, round(depth * w / sum(w))),
      stringsAsFactors = FALSE
    )
  }
  for (r in 1:3) {
    run <- paste0("R", r)
    for (i in 1:5) {
      s <- sprintf("S%d%d", r, i)
      for (m in c("M1", "M2")) {
        if (!is.null(fail_run) && m == "M2" && run == fail_run) {
          add(s, m, run, sample(field_pool, 4), 150)
        } else {
          add(s, m, run, sample(field_pool[1:40 + (r - 1) * 20], 30), 20000)
        }
      }
    }
  }
  for (m in c("M1", "M2")) {
    add("CLEAN", m, "R1", lab, 800)
    add("MISLABEL", m, "R2", sample(field_pool[21:60], 30), 20000)
    add("PLANKTON", m, "R3", sample(plankton_pool, 60), 20000)
  }
  do.call(rbind, rows)
}

