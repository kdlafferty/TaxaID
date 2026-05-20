# ---- %||% null coalescing operator -------------------------------------------

test_that("%||% returns RHS when LHS is NULL", {
  expect_equal(NULL %||% 5, 5)
  expect_equal(NULL %||% "hello", "hello")
})

test_that("%||% returns LHS when LHS is not NULL", {
  expect_equal(3 %||% 5, 3)
  expect_equal("a" %||% "b", "a")
  expect_equal(FALSE %||% TRUE, FALSE)
})

test_that("%||% does NOT treat empty string as NULL", {
  expect_equal("" %||% "fallback", "")
})

test_that("%||% does NOT treat NA as NULL", {
  expect_identical(NA %||% "fallback", NA)
})
