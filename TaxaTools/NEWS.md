# TaxaTools 1.0.0

* First public release.
* Cleans, verifies and standardizes taxonomic names, including spell-checking
  and correcting species names, and building standardized labels at any rank.
* Translates names between taxonomic backbones (GBIF, NCBI, WoRMS) and
  retrieves classification hierarchies through their APIs.
* Provides the LLM provider functions the rest of the ecosystem calls
  (Anthropic, OpenAI, Azure OpenAI, Gemini and Ollama), with chunking, a model
  registry with capability tiers, and token accounting.
* Drafts methods and results text, and assembles run reports, for the other
  packages to extend.
