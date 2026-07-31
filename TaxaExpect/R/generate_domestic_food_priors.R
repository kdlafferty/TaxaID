#' Default domestic animal taxa
#'
#' A starting list of common domestic/commensal animal species. Not
#' exhaustive -- extend or replace via \code{generate_domestic_food_priors(
#' domestic_animal_taxa = ...)} for your own study system.
#' @noRd
.default_domestic_animal_taxa <- c(
  "Homo sapiens",
  "Canis lupus",
  "Felis catus",
  "Bos taurus",
  "Ovis aries",
  "Capra hircus",
  "Sus scrofa",
  "Equus caballus",
  "Equus asinus",
  "Gallus gallus",
  "Anas platyrhynchos",
  "Meleagris gallopavo",
  "Oryctolagus cuniculus"
)

#' Default food/crop species taxa
#'
#' An extensive list of human food/crop species (449 taxa, including a
#' short set of common cultivated food fungi), distinct from
#' \code{domestic_animal_taxa} -- these represent food-handling/lab-bench/
#' sample-processing contamination risk, not pet/livestock/ranch runoff.
#'
#' @section Provenance:
#' Built by cross-referencing the union of two real candidate cultivated-
#' plant source files (\code{Cultivated_plants.csv}/\code{Food_Plants_Taxonomy.csv},
#' 666 unique species after dedup) against a food-crop genus reference
#' compiled from five Wikipedia food-plant lists (vegetables, culinary
#' fruits, culinary nuts, culinary herbs and spices, edible seeds/cereals/
#' legumes -- 305 genera after two rounds of spot-check-driven extension).
#' Real false positives found and corrected during that process: a bare
#' genus match is not always food-relevant even when SOME species in that
#' genus are (\code{Iris}, \code{Eucalyptus globulus}, \code{Acacia mearnsii}
#' were moved to \code{\link{.default_known_cultivar_taxa}} instead). Real
#' false negatives found and added: several genuine but less globally-
#' mainstream food genera (\emph{Theobroma}, \emph{Psophocarpus},
#' \emph{Parkia}, \emph{Claytonia}, \emph{Trapa}, \emph{Chaerophyllum}, etc.)
#' were missing from the first-pass genus reference. A handful of cultivated
#' food fungi (\emph{Agaricus bisporus}, \emph{Pleurotus} spp., etc.) were
#' found mixed into the source CSVs (a diet-study data source, not plant-only)
#' and folded in here directly as a short fixed list, rather than opening a
#' live discovery channel across the whole Fungi kingdom.
#' Not exhaustive, and genus-level classification against an inherently
#' incomplete reference has a real residual error rate -- extend or replace
#' via \code{generate_domestic_food_priors(food_species_taxa = ...)} for your
#' own study system.
#' @noRd
.default_food_species_taxa <- c(
  "Abelmoschus caillei",
  "Abelmoschus esculentus",
  "Acacia senegal",
  "Acacia seyal",
  "Acmella oleracea",
  "Actinidia arguta",
  "Actinidia deliciosa",
  "Aegle marmelos",
  "Aframomum melegueta",
  "Agaricus bisporus",
  "Agrocybe aegerita",
  "Allium ampeloprasum",
  "Allium cepa",
  "Allium fistulosum",
  "Allium sativum",
  "Allium schoenoprasum",
  "Allium wakegi",
  "Allium x proliferum",
  "Aloysia citrodora",
  "Amaranthus",
  "Amaranthus cruentus",
  "Amaranthus viridis",
  "Amomum subulatum",
  "Amorphophallus konjac",
  "Amorphophallus paeoniifolius",
  "Anacardium occidentale",
  "Ananas comosus",
  "Anethum foeniculum",
  "Anethum graveolens",
  "Annona",
  "Annona cherimola",
  "Annona glabra",
  "Annona montana",
  "Annona mucosa",
  "Annona muricata",
  "Annona purpurea",
  "Annona reticulata",
  "Annona squamosa",
  "Annona x",
  "Anthriscus cerefolium",
  "Apium graveolens",
  "Arachis hypogaea",
  "Arachis pintoi",
  "Areca catechu",
  "Armoracia rusticana",
  "Aronia",
  "Aronia arbutifolia",
  "Aronia melanocarpa",
  "Aronia prunifolia",
  "Aronia x prunifolia",
  "Artemisia absinthium",
  "Artemisia dracunculus",
  "Artocarpus altilis",
  "Artocarpus heterophyllus",
  "Artocarpus hypargyraea",
  "Artocarpus hypargyreus",
  "Artocarpus integer",
  "Artocarpus lacucha",
  "Artocarpus lakoocha",
  "Artocarpus odoratissimus",
  "Auricularia auricula-judae",
  "Avena sativa",
  "Averrhoa bilimbi",
  "Averrhoa carambola",
  "Basella alba",
  "Benincasa fistulosa",
  "Benincasa hispida",
  "Bertholletia excelsa",
  "Beta vulgaris",
  "Brassica carinata",
  "Brassica juncea",
  "Brassica napobrassica",
  "Brassica napus",
  "Brassica nigra",
  "Brassica oleracea",
  "Brassica rapa",
  "Cajanus cajan",
  "Capparis spinosa",
  "Capsicum",
  "Capsicum annuum",
  "Capsicum baccatum",
  "Capsicum chinense",
  "Capsicum frutescens",
  "Capsicum pubescens",
  "Capsicum spp",
  "Carica papaya",
  "Carthamus tinctorius",
  "Carum carvi",
  "Carya illinoensis",
  "Carya illinoinensis",
  "Casimiroa edulis",
  "Castanea sativa",
  "Cenchrus americanus",
  "Centella asiatica",
  "Ceratonia siliqua",
  "Chaerophyllum bulbosum",
  "Chenopodium album",
  "Chenopodium ambrosioides",
  "Chenopodium bonus-henricus",
  "Chenopodium quinoa",
  "Chrysophyllum albidum",
  "Chrysophyllum cainito",
  "Cicer arietinum",
  "Cichorium endivia",
  "Cichorium intybus",
  "Cinnamomum aromaticum",
  "Cinnamomum burmanni",
  "Cinnamomum burmannii",
  "Cinnamomum cassia",
  "Cinnamomum loureiroi",
  "Cinnamomum verum",
  "Citrofortunella microcarpa",
  "Citrullus lanatus",
  "Citrus",
  "Citrus aurantifolia",
  "Citrus aurantium",
  "Citrus bergamia",
  "Citrus hystrix",
  "Citrus japonica",
  "Citrus limetta",
  "Citrus limon",
  "Citrus maxima",
  "Citrus medica",
  "Citrus paradisi",
  "Citrus reticulata",
  "Citrus sinensis",
  "Citrus unshiu",
  "Citrus x",
  "Citrus x aurantiifolia",
  "Citrus x aurantium",
  "Citrus x limon",
  "Citrus x microcarpa",
  "Citrus x paradisi",
  "Claytonia perfoliata",
  "Cocos nucifera",
  "Cola acuminata",
  "Colocasia esculenta",
  "Coriandrum sativum",
  "Corylus avellana",
  "Crataegus azarolus",
  "Crataegus pinnatifida",
  "Crocus",
  "Crocus sativus",
  "Cucumis anguria",
  "Cucumis melo",
  "Cucumis metuliferus",
  "Cucumis sativus",
  "Cucurbita ficifolia",
  "Cucurbita maxima",
  "Cucurbita mixta",
  "Cucurbita moschata",
  "Cucurbita pepo",
  "Cuminum cyminum",
  "Curcuma longa",
  "Cyclanthera pedata",
  "Cydonia oblonga",
  "Cymbopogon citratus",
  "Cymbopogon nardus",
  "Cyperus esculentus",
  "Daucus carota",
  "Digitaria exilis",
  "Digitaria sanguinalis",
  "Dimocarpus longan",
  "Dioscorea",
  "Dioscorea bulbifera",
  "Dioscorea cayenensis",
  "Dioscorea opposita",
  "Dioscorea oppositifolia",
  "Dioscorea rotundata",
  "Diospyros blancoi",
  "Diospyros digyna",
  "Diospyros kaki",
  "Diospyros lotus",
  "Diospyros malabarica",
  "Diospyros mespiliformis",
  "Diospyros virginiana",
  "Dysphania ambrosioides",
  "Elaeis guineensis",
  "Elaeis oleifera",
  "Eleocharis dulcis",
  "Elettaria cardamomum",
  "Eleusine coracana",
  "Elwendia persica",
  "Eragrostis tef",
  "Eriobotrya japonica",
  "Eruca sativa",
  "Eruca vesicaria",
  "Eryngium foetidum",
  "Euterpe oleracea",
  "Fagopyrum esculentum",
  "Ficus carica",
  "Ficus elastica",
  "Flammulina velutipes",
  "Foeniculum vulgare",
  "Fragaria",
  "Fragaria x",
  "Garcinia cowa",
  "Garcinia humilis",
  "Garcinia livingstonei",
  "Garcinia madruno",
  "Garcinia mangostana",
  "Garcinia prainiana",
  "Garcinia tinctoria",
  "Genipa americana",
  "Glycine max",
  "Glycyrrhiza glabra",
  "Gynura bicolor",
  "Gynura procumbens",
  "Helianthus annuus",
  "Helianthus tuberosus",
  "Hericium erinaceus",
  "Hordeum vulgare",
  "Houttuynia cordata",
  "Hylocereus costaricensis",
  "Hylocereus megalanthus",
  "Hylocereus undatus",
  "Hyssopus officinalis",
  "Illicium verum",
  "Ipomoea aquatica",
  "Ipomoea batatas",
  "Jasminum",
  "Jasminum officinale",
  "Juglans regia",
  "Juniperus communis",
  "Lactuca sativa",
  "Lagenaria siceraria",
  "Lathyrus sativus",
  "Lathyrus tuberosus",
  "Laurus nobilis",
  "Lavandula",
  "Lavandula angustifolia",
  "Lecythis zabucajo",
  "Lens culinaris",
  "Lentinula edodes",
  "Levisticum officinale",
  "Limonia acidissima",
  "Linum usitatissimum",
  "Litchi chinensis",
  "Lithocarpus edulis",
  "Luffa acutangula",
  "Luffa aegyptiaca",
  "Macadamia",
  "Malpighia glabra",
  "Malus domestica",
  "Malus sylvestris",
  "Mangifera caesia",
  "Mangifera foetida",
  "Mangifera indica",
  "Mangifera odorata",
  "Manihot esculenta",
  "Manilkara zapota",
  "Maranta arundinacea",
  "Melicoccus bijugatus",
  "Melissa officinalis",
  "Mentha",
  "Mentha arvensis",
  "Mentha pulegium",
  "Mentha spicata",
  "Mentha x",
  "Mespilus germanica",
  "Momordica charantia",
  "Momordica cochinchinensis",
  "Momordica dioica",
  "Moringa oleifera",
  "Moringa stenopetala",
  "Morus",
  "Morus alba",
  "Morus nigra",
  "Morus rubra",
  "Musa",
  "Musa balbisiana",
  "Musa textilis",
  "Myristica fragrans",
  "Myrrhis odorata",
  "Nasturtium officinale",
  "Nelumbo nucifera",
  "Nephelium hypoleucum",
  "Nephelium lappaceum",
  "Nephelium mutabile",
  "Nigella sativa",
  "Ocimum",
  "Ocimum basilicum",
  "Ocimum tenuiflorum",
  "Opuntia ficus-indica",
  "Origanum majorana",
  "Origanum vulgare",
  "Oryza glaberrima",
  "Oryza sativa",
  "Pandanus amaryllifolius",
  "Panicum miliaceum",
  "Papaver somniferum",
  "Parkia speciosa",
  "Passiflora edulis",
  "Passiflora ligularis",
  "Passiflora quadrangularis",
  "Pereskia aculeata",
  "Perilla frutescens",
  "Persea americana",
  "Petroselinum crispum",
  "Phaseolus acutifolius",
  "Phaseolus coccineus",
  "Phaseolus lunatus",
  "Phaseolus vulgaris",
  "Phoenix dactylifera",
  "Phoenix sylvestris",
  "Physalis peruviana",
  "Physalis philadelphica",
  "Pimenta dioica",
  "Pimpinella anisum",
  "Pinus gerardiana",
  "Pinus koraiensis",
  "Pinus pinea",
  "Pinus sibirica",
  "Pinus sylvestris",
  "Piper betle",
  "Piper chaba",
  "Piper methysticum",
  "Piper nigrum",
  "Piper retrofractum",
  "Piper sarmentosum",
  "Pistacia vera",
  "Pisum sativum",
  "Pleurotus citrinopileatus",
  "Pleurotus eryngii",
  "Pleurotus ostreatus",
  "Pleurotus pulmonarius",
  "Portulaca oleracea",
  "Pouteria caimito",
  "Pouteria campechiana",
  "Pouteria sapota",
  "Praecitrullus fistulosus",
  "Prunus armeniaca",
  "Prunus avium",
  "Prunus cerasifera",
  "Prunus cerasus",
  "Prunus domestica",
  "Prunus dulcis",
  "Prunus persica",
  "Psidium",
  "Psidium acutangulum",
  "Psidium cattleianum",
  "Psidium cattleyanum",
  "Psidium guajava",
  "Psidium littorale",
  "Psophocarpus tetragonolobus",
  "Punica granatum",
  "Pyrus bretschneideri",
  "Pyrus communis",
  "Pyrus pyrifolia",
  "Pyrus x bretschneideri",
  "Ribes",
  "Ribes alpinum",
  "Ribes hirtellum",
  "Ribes nigrum",
  "Ribes rubrum",
  "Ribes uva-crispa",
  "Rosa",
  "Rosa canina",
  "Rosa rubiginosa",
  "Rosmarinus officinalis",
  "Rubus fruticosus",
  "Rubus idaeus",
  "Rubus phoenicolasius",
  "Rubus plicatus",
  "Rubus spectabilis",
  "Rumex acetosa",
  "Ruta graveolens",
  "Salvia hispanica",
  "Salvia officinalis",
  "Salvia rosmarinus",
  "Sambucus nigra",
  "Satureja hortensis",
  "Satureja montana",
  "Secale cereale",
  "Sechium edule",
  "Selenicereus costaricensis",
  "Selenicereus megalanthus",
  "Selenicereus undatus",
  "Sesamum indicum",
  "Setaria italica",
  "Sinapis alba",
  "Smyrnium olusatrum",
  "Solanum aethiopicum",
  "Solanum betaceum",
  "Solanum centrale",
  "Solanum lycopersicum",
  "Solanum macrocarpon",
  "Solanum melongena",
  "Solanum muricatum",
  "Solanum quitoense",
  "Solanum sessiliflorum",
  "Solanum tuberosum",
  "Sorghum bicolor",
  "Spinacia oleracea",
  "Spondias dulcis",
  "Spondias mombin",
  "Spondias purpurea",
  "Syzygium aqueum",
  "Syzygium aromaticum",
  "Syzygium cumini",
  "Syzygium jambos",
  "Syzygium malaccense",
  "Syzygium nervosum",
  "Syzygium samarangense",
  "Tanacetum cinerariifolium",
  "Tanacetum parthenium",
  "Taraxacum officinale",
  "Theobroma cacao",
  "Trachyspermum ammi",
  "Trapa bicornis",
  "Trapa natans",
  "Tremella fuciformis",
  "Tricholoma matsutake",
  "Trigonella foenum-graecum",
  "Triticum aestivum",
  "Triticum dicoccum",
  "Triticum durum",
  "Triticum monococcum",
  "Triticum spelta",
  "Triticum turanicum",
  "Triticum turgidum",
  "Vaccinium",
  "Vaccinium corymbosum",
  "Vaccinium macrocarpon",
  "Vaccinium myrtillus",
  "Vanilla planifolia",
  "Vicia ervilia",
  "Vicia faba",
  "Vicia sativa",
  "Vigna aconitifolia",
  "Vigna angularis",
  "Vigna mungo",
  "Vigna radiata",
  "Vigna subterranea",
  "Vigna umbellata",
  "Vigna unguiculata",
  "Vitis vinifera",
  "Volvariella volvacea",
  "Wasabia japonica",
  # "x Triticosecale" (leading lowercase "x", standard botanical hybrid
  # notation) verified to clean to NA via TaxaTools::clean_taxon_names()
  # (the capital-letter-start filter rejects it) and so was silently
  # dropped from this list every call, unlike "Citrus x aurantiifolia"-style
  # entries elsewhere in this list, which lossily but successfully collapse
  # to genus-only. Corrected to the bare genus, matching how this list
  # already handles other genus-only entries.
  "Triticosecale",
  "Xanthosoma sagittifolium",
  "Zanthoxylum",
  "Zanthoxylum sp.",
  "Zea mays",
  "Zingiber officinale",
  "Zizania",
  "Ziziphus",
  "Ziziphus mauritiana",
  "Ziziphus zizyphus"
)

#' Default known cultivated/ornamental (non-food) plant taxa
#'
#' A fixed list of ~216 species known to be cultivated somewhere (gardens,
#' landscaping, dye/fiber/medicinal/forage crops) but not primarily as human
#' food -- the third fixed "patch" list, alongside
#' \code{\link{.default_domestic_animal_taxa}}/\code{\link{.default_food_species_taxa}}.
#' Checked immediately against a match-list candidate the same way the other
#' two are (no live iNaturalist confirmation required) -- distinct from the
#' open-ended live-discovery channel (\code{candidate_plant_taxa} and the
#' automatic match-list residual step), which exists specifically to catch
#' cultivated species NOT anticipated by any fixed list.
#'
#' @section Provenance:
#' Same source/method as \code{\link{.default_food_species_taxa}} -- see that
#' object's \code{@section Provenance} for the full record. This is the
#' complementary "genus matched, but not classified as food" half of the same
#' classification pass. Known limitations, not fully resolved: some entries
#' are food/beverage-adjacent rather than purely ornamental (e.g.
#' \emph{Coffea}, \emph{Camellia sinensis} -- tea/coffee, left here as
#' beverage rather than food crops) or algae rather than land plants (e.g.
#' \emph{Ulva lactuca}, a real edible seaweed genus-matched only against a
#' land-plant reference) -- harmless for this list's own mechanism (a fixed
#' patch has no taxonomic-scope restriction to violate), but worth knowing if
#' you rely on the categorical distinction being perfectly clean.
#' @noRd
.default_known_cultivar_taxa <- c(
  "Acacia mearnsii",
  "Acca sellowiana",
  "Acer saccharum",
  "Agave fourcroydes",
  "Agave sisalana",
  "Agave tequilana",
  "Alibertia patinoi",
  "Aloe vera",
  "Antidesma bunius",
  "Apios americana",
  "Arbutus unedo",
  "Arracacia xanthorrhiza",
  "Asimina triloba",
  "Aspalathus linearis",
  "Asparagus officinalis",
  "Aster",
  "Astrocaryum vulgare",
  "Azadirachta indica",
  "Baccaurea ramiflora",
  "Bactris gasipaes",
  "Bambusa oldhamii",
  "Bambusa vulgaris",
  "Bellis perennis",
  "Blighia sapida",
  "Blitum bonus-henricus",
  "Boehmeria nivea",
  "Borassus flabellifer",
  "Borojoa patinoi",
  "Boswellia sacra",
  "Bouea macrophylla",
  "Bunium persicum",
  "Byrsonima crassifolia",
  "Calendula officinalis",
  "Camelina sativa",
  "Camellia sinensis",
  "Cananga odorata",
  "Canavalia ensiformis",
  "Cannabis sativa",
  "Carissa carandas",
  "Carissa macrocarpa",
  "Catha edulis",
  "Ceiba pentandra",
  "Celtis australis",
  "Chrysanthemum",
  "Chrysobalanus icaco",
  "Chrysopogon zizanioides",
  "Cinchona",
  "Clausena lansium",
  "Clitoria ternatea",
  "Coccinia grandis",
  "Coccoloba uvifera",
  "Coffea",
  "Coffea arabica",
  "Coffea canephora",
  "Coffea liberica",
  "Coix lacryma-jobi",
  "Coleus rotundifolius",
  "Commiphora gileadensis",
  "Commiphora myrrha",
  "Corchorus capsularis",
  "Corchorus olitorius",
  "Crambe maritima",
  "Crotalaria juncea",
  "Cyamopsis tetragonoloba",
  "Cynara cardunculus",
  "Dacryodes edulis",
  "Dahlia",
  "Dianthus",
  "Dillenia",
  "Dillenia serrata",
  "Dovyalis caffra",
  "Dovyalis hebecarpa",
  "Durio zibethinus",
  "Echinochloa esculenta",
  "Echinochloa frumentacea",
  "Elaeagnus multiflora",
  "Ensete ventricosum",
  "Erythroxylum coca",
  "Eucalyptus globulus",
  "Eugenia aggregata",
  "Eugenia brasiliensis",
  "Eugenia luschnathiana",
  "Eugenia stipitata",
  "Eugenia uniflora",
  "Eugenia victoriana",
  "Eutrema japonicum",
  "Faidherbia albida",
  "Flacourtia indica",
  "Freesia",
  "Furcraea andina",
  "Gambeya albida",
  "Gerbera",
  "Gossypium arboreum",
  "Gossypium barbadense",
  "Gossypium hirsutum",
  "Grewia asiatica",
  "Guizotia abyssinica",
  "Helicteres isora",
  "Hevea brasiliensis",
  "Hibiscus cannabinus",
  "Hibiscus sabdariffa",
  "Humulus lupulus",
  "Hyacinthus orientalis",
  "Hypericum perforatum",
  "Ilex paraguariensis",
  "Indigofera tinctoria",
  "Iris",
  "Lablab purpureus",
  "Lansium domesticum",
  "Lawsonia inermis",
  "Lepidium meyenii",
  "Lepidium sativum",
  "Lespedeza",
  "Lonicera caerulea",
  "Lotus",
  "Lupinus",
  "Lupinus albus",
  "Lupinus angustifolius",
  "Lupinus luteus",
  "Lupinus mutabilis",
  "Lycium barbarum",
  "Lycium chinense",
  "Maclura tinctoria",
  "Macrotyloma geocarpum",
  "Macrotyloma uniflorum",
  "Mammea americana",
  "Matricaria chamomilla",
  "Matricaria recutita",
  "Mauritia flexuosa",
  "Medicago sativa",
  "Mesembryanthemum crystallinum",
  "Metroxylon sagu",
  "Milicia excelsa",
  "Morella rubra",
  "Morinda citrifolia",
  "Mucuna pruriens",
  "Myrciaria cauliflora",
  "Myrica rubra",
  "Narcissus",
  "Nicotiana tabacum",
  "Oldenlandia umbellata",
  "Olea europaea",
  "Onobrychis viciifolia",
  "Oxalis tuberosa",
  "Pachyrhizus erosus",
  "Panax",
  "Pastinaca sativa",
  "Pennisetum glaucum",
  "Phacelia tanacetifolia",
  "Phalaris canariensis",
  "Phleum pratense",
  "Phormium tenax",
  "Phyllanthus acidus",
  "Phyllanthus emblica",
  "Phyllostachys edulis",
  "Picea abies",
  "Plantago coronopus",
  "Plectranthus rotundifolius",
  "Plinia cauliflora",
  "Pogostemon cablin",
  "Pseudopodospermum hispanicum",
  "Pueraria lobata",
  "Pueraria montana",
  "Raphanus sativus",
  "Rhamnus prinoides",
  "Rhaphiolepis bibas",
  "Rheum",
  "Ricinus communis",
  "Rollinia mucosa",
  "Rubia tinctorum",
  "Saccharum officinarum",
  "Salacca zalacca",
  "Sandoricum koetjape",
  "Santolina chamaecyparissus",
  "Scorzonera hispanica",
  "Senegalia senegal",
  "Sesbania grandiflora",
  "Sicana odorifera",
  "Sicyos edulis",
  "Simmondsia chinensis",
  "Siraitia grosvenorii",
  "Smallanthus sonchifolius",
  "Stelechocarpus burahol",
  "Stevia rebaudiana",
  "Synsepalum dulcificum",
  "Tagetes",
  "Talisia esculenta",
  "Tamarindus indica",
  "Tectona grandis",
  "Telfairia occidentalis",
  "Thymus vulgaris",
  "Tragopogon porrifolius",
  "Triadica sebifera",
  "Trichosanthes cucumerina",
  "Trichosanthes dioica",
  "Trifolium",
  "Trifolium incarnatum",
  "Trifolium pratense",
  "Trifolium repens",
  "Tropaeolum tuberosum",
  "Tulipa",
  "Ulva lactuca",
  "Vachellia seyal",
  "Valeriana officinalis",
  "Valerianella locusta",
  "Vangueria madagascariensis",
  "Vasconcellea",
  "Vasconcellea cundinamarcensis",
  "Vasconcellea pentagona",
  "Vasconcellea pubescens",
  "Vernicia fordii",
  "Vernonia",
  "Vernonia calvoana",
  "Vitellaria paradoxa",
  "Willughbeia",
  "Willughbeia sarawakensis"
)

#' Generate priors for domestic, commensal, and food-associated species
#'
#' Constructs Beta(alpha, beta) prior rows for named domestic/commensal
#' animal species, human food/crop species, and (optionally) candidate
#' cultivated/ornamental plants -- the three-channel design from
#' \code{ecosystem_docs/REENTRY_PROMPT_domestic_food_species_priors.md}.
#' Unlike \code{\link{generate_undetected_diversity}}'s anonymous Tier 3
#' proxies, every row here carries a real \code{taxon_name} and a
#' \code{prior_source_type} category for downstream systematic handling
#' (reporting, exclusion from biodiversity summaries, routing to review).
#'
#' @section Why this exists:
#' GBIF/iNaturalist-derived occurrence data structurally under-index
#' captive/cultivated organisms (pets, livestock, garden/crop plants), so
#' these species get the same tiny \code{generate_undetected_diversity()}
#' global-floor prior as a genuinely implausible candidate -- not because
#' they are rare, but because the occurrence database under-counts them.
#' This function is a non-GBIF prior source for exactly that gap, using
#' \code{TaxaFetch::fetch_inat_occurrences()} (which can include
#' \code{quality_grade = "casual"}/\code{captive = "any"} records that
#' standard occurrence indexing excludes) as evidence.
#'
#' @section Four fixed-list channels, plus one open-discovery channel:
#' \describe{
#'   \item{\code{domestic_animal_taxa}}{A fixed, user-editable vector
#'     (pre-populated with common defaults: dog, cat, cow, sheep, pig,
#'     chicken, horse, \code{Homo sapiens}, etc.). Patched immediately --
#'     membership alone earns a baseline prior, no live check required.}
#'   \item{\code{food_species_taxa}}{A separate fixed vector for human
#'     food/crop species (tomato, onion, etc., plus a short list of
#'     cultivated food fungi) -- a distinct contamination category from
#'     \code{domestic_animal_taxa} (food-handling/lab-bench/sample-
#'     processing contamination, not pet/livestock/ranch runoff). Marker
#'     relevance varies: irrelevant for vertebrate-specific markers (e.g.
#'     12S MiFish), directly relevant for plant/algae-inclusive markers
#'     (e.g. 18S). Patched immediately, same as \code{domestic_animal_taxa}.}
#'   \item{\code{known_cultivar_taxa}}{A third fixed vector: species known
#'     to be cultivated somewhere (ornamental/dye/fiber/forage/medicinal)
#'     but not primarily as food. Patched immediately, same as the two
#'     channels above -- membership on this list is itself the evidence, no
#'     live iNaturalist confirmation needed. \code{prior_source_type =
#'     "domestic_plant"} (shared with the open-discovery channel below;
#'     see \code{cultivar_evidence_source} in \code{@return} for which
#'     mechanism actually produced a given row).}
#'   \item{\code{candidate_plant_taxa}}{User-supplied candidates that
#'     genuinely require live confirmation -- unlike the three fixed lists
#'     above, membership here is NOT itself sufficient evidence.
#'     Each is checked against \code{TaxaFetch::fetch_inat_occurrences(
#'     captive = "any", quality_grade = "casual")} and only receives a
#'     prior row if that check finds real local casual-grade
#'     (cultivated/garden) evidence. Default \code{NULL}.}
#'   \item{Open discovery (automatic, requires \code{match_list_taxa})}{
#'     The reason a live-check channel exists at all: a fixed list, however
#'     extensive, cannot anticipate every real cultivated escapee. When
#'     \code{match_list_taxa} is supplied, any match-list taxon not already
#'     covered by a fixed list or an existing modelled prior
#'     (\code{taxaexpect_priors}), and whose \code{taxonomy}-supplied
#'     \code{phylum} is \code{"Streptophyta"} or \code{"Tracheophyta"}
#'     (land plants -- both spellings needed, since
#'     \code{TaxaMatch::convert_taxonomy_backbone()}'s per-column NCBI
#'     fallback means either can legitimately appear in one dataset), is
#'     added as an open candidate for exactly this reason -- deliberately
#'     NOT pre-restricted to \code{known_cultivar_taxa} or any other list,
#'     since restricting the discovery channel to what's already known
#'     would defeat its purpose. See \code{@section Match-list gating}.}
#' }
#'
#' @section Name normalization:
#' Every candidate name (from all three channels, including user-supplied
#' overrides) is passed through \code{TaxaTools::clean_taxon_names()} before
#' becoming a row's \code{taxon_name} -- the same cleaner
#' \code{match_obj$taxon_name} values are normalized through elsewhere in this
#' ecosystem, which truncates to genus + epithet only (e.g. a subspecies
#' trinomial like \emph{"Sus scrofa domesticus"} becomes \emph{"Sus scrofa"};
#' a hybrid-formula name like \emph{"Fragaria x ananassa"} becomes
#' genus-only \emph{"Fragaria"}, since \code{"x"} is treated as an
#' abbreviation token). \code{TaxaAssign::join_priors()} joins on an exact
#' \code{taxon_name} string match, so an uncleaned candidate name would
#' silently never join to a real query's (cleaned) result. A name that
#' cannot be cleaned to a valid binomial/genus is dropped with a
#' \code{warning()} rather than passed through as-is.
#'
#' @section Match-list gating:
#' \code{match_list_taxa = NULL} (the default) preserves this function's
#' original behavior exactly: every fixed-list channel is checked in full,
#' regardless of whether those taxa have any bearing on your actual data.
#' This is simple and fully backward compatible, but wasteful in a real
#' workflow -- most fixed-list taxa were never even detected this run, so
#' checking them (each a real iNaturalist API call) buys nothing.
#'
#' Supplying \code{match_list_taxa} (the taxa that actually have a
#' likelihood this run -- e.g. \code{unique(match_obj$species)} or
#' \code{unique(lik_result$likelihoods$taxon_name[taxon_name_rank ==
#' "species"])}) changes this: every channel (the three fixed lists AND
#' any user-supplied \code{candidate_plant_taxa}) is first restricted to
#' the intersection with \code{match_list_taxa}, and the residual --
#' match-list taxa left over after that restriction and after excluding
#' anything already carrying a named prior in \code{taxaexpect_priors} --
#' becomes the pool for the open-discovery channel described above. This
#' is the actual point of supplying it: fewer, more meaningful iNaturalist
#' calls (most real candidates are already covered by a fixed list or
#' already have real GBIF evidence), and a genuine chance to catch a
#' cultivated species nothing anticipated.
#'
#' \code{taxaexpect_priors} is optional even when \code{match_list_taxa} is
#' supplied -- omitting it just means the residual pool is a superset of
#' the minimum necessary (a few more candidates get checked than strictly
#' needed), never a correctness problem.
#'
#' The open-discovery step is silently skipped (with a \code{message()},
#' not a \code{warning()}) whenever \code{taxonomy} lacks a \code{phylum}
#' column -- there is no safe way to scope an unrestricted live-check pool
#' to plausible taxa without it, and checking, say, every unreferenced
#' protozoan or diatom against iNaturalist would be both wasteful and
#' pointless.
#'
#' @section What this does NOT fix:
#' Cross-genus reference gaps (e.g. \emph{Bison bison} anchored reads with
#' \emph{Bos taurus} never proposed as a candidate for that specific
#' observation) are unaffected -- \code{TaxaLikely::restore_suppressed_candidates()}
#' only pulls same-genus congeners. This function only changes the PRIOR
#' for a species already under consideration; it does not expand candidate
#' sets. See \code{[[project_taxaflag_domestic_species_floor_note]]} for the
#' full real-data finding this design responds to, including why
#' \emph{Homo sapiens} sequence-level resolution already works fine without
#' this fix (strong matches resolve correctly regardless of prior magnitude)
#' -- this function's value is the categorical flag plus help for weaker/
#' degraded matches, not sequence resolution itself.
#'
#' @param model_obj A biofreq_model object (output of
#'   \code{train_biodiversity_model()}), used only for its \code{N_total}
#'   and \code{meta$habitat_col} so these rows sit on the same theta scale
#'   as \code{generate_undetected_diversity()}'s output.
#' @param lat,lng Numeric. Query site coordinates for the iNaturalist search.
#' @param grid_id Character. Grid cell identifier to attach to every row
#'   (for joining into \code{taxaexpect_priors}). Default \code{NA_character_}.
#' @param domestic_animal_taxa Character vector of domestic/commensal animal
#'   taxon names. Default \code{.default_domestic_animal_taxa} (a starting
#'   list -- extend for your study system). Set to \code{character(0)} to
#'   disable this channel. Normalized via \code{TaxaTools::clean_taxon_names()}
#'   before use -- see \code{@section Name normalization}.
#' @param food_species_taxa Character vector of food/crop species taxon
#'   names. Default \code{.default_food_species_taxa}. Set to
#'   \code{character(0)} to disable this channel. Normalized the same way as
#'   \code{domestic_animal_taxa}.
#' @param known_cultivar_taxa Character vector of known cultivated/ornamental
#'   (non-food) plant taxon names. Default \code{.default_known_cultivar_taxa}.
#'   Set to \code{character(0)} to disable this channel. Normalized the same
#'   way as \code{domestic_animal_taxa}. Patched immediately like the two
#'   fixed lists above -- see \code{@section Four fixed-list channels}.
#' @param candidate_plant_taxa Character vector of candidate plant-kingdom
#'   taxon names to check for real local cultivated/casual-grade iNaturalist
#'   evidence. Default \code{NULL} (channel disabled -- no live iNaturalist
#'   calls are made unless you supply candidates here, or unless
#'   \code{match_list_taxa} produces open-discovery candidates). Normalized
#'   the same way as \code{domestic_animal_taxa}.
#' @param match_list_taxa Optional character vector of taxa that actually
#'   have a likelihood in this run (e.g. from \code{match_obj}/
#'   \code{lik_result}). Default \code{NULL} (no gating -- every fixed-list
#'   channel is checked in full, the original behavior). See
#'   \code{@section Match-list gating}.
#' @param taxaexpect_priors Optional data frame (or just its \code{taxon_name}
#'   column) of already-modelled priors, used only to shrink the
#'   open-discovery residual pool when \code{match_list_taxa} is supplied --
#'   a match-list taxon with a real named row here doesn't need an
#'   iNaturalist check. Default \code{NULL} (residual pool is a safe
#'   superset, not incorrect, just less minimal).
#' @param radius_km Numeric. iNaturalist search radius. Default 50.
#' @param ess Numeric. Baseline effective sample size (in the same
#'   \code{N_total} units as \code{generate_undetected_diversity()}'s
#'   \code{singleton_ess}) assumed for \code{domestic_animal_taxa}/
#'   \code{food_species_taxa} even with zero local iNaturalist evidence --
#'   these categories are plausible almost anywhere. Default 5.
#' @param max_ess Numeric. Cap on the evidence-boosted effective sample
#'   size, so a very large local iNaturalist count cannot dominate
#'   \code{N_total}. Default 50.
#' @param taxonomy Optional data frame with columns \code{taxon_name} and
#'   any subset of \code{genus}, \code{family}, \code{order}, \code{class},
#'   \code{phylum}, joined onto the result the same way
#'   \code{generate_undetected_diversity(taxonomy = ...)} does. Default
#'   \code{NULL}. When a \code{kingdom} column is also present, it additionally
#'   enables the iNaturalist kingdom cross-check (see \code{inat_kingdom_mismatch}
#'   in \code{@return}) -- without it, a mismatched-homonym result cannot be
#'   detected and is trusted as-is. When a \code{phylum} column is present
#'   AND \code{match_list_taxa} is supplied, it additionally enables the
#'   open-discovery residual step (see \code{@section Match-list gating}) --
#'   without it, that step is skipped with a message.
#' @param api_token Character. iNaturalist API token, forwarded to
#'   \code{TaxaFetch::fetch_inat_occurrences()}. Defaults to the
#'   \code{INAT_API_TOKEN} environment variable.
#' @param verbose Logical. Print progress. Default FALSE.
#'
#' @return A tibble with one row per resolved domestic/food/plant taxon:
#'   \describe{
#'     \item{taxon_name}{The real taxon name (never NA, unlike
#'       \code{generate_undetected_diversity()}'s anonymous proxies).}
#'     \item{grid_id}{As supplied.}
#'     \item{alpha, beta}{Beta(alpha, beta) prior parameters.}
#'     \item{theta_mean, theta_sd}{Derived from alpha/beta.}
#'     \item{model_tier}{Always \code{"tier_domestic_food"} -- deliberately
#'       distinct from \code{"tier3_undetected"} so downstream code can
#'       tell a named domestic/food prior apart from an anonymous dark-
#'       diversity proxy.}
#'     \item{prior_source_type}{One of \code{"domestic_animal"},
#'       \code{"food_species"}, \code{"domestic_plant"} -- the categorical
#'       column this function exists to add. \code{"domestic_plant"} is
#'       shared by \code{known_cultivar_taxa}, \code{candidate_plant_taxa},
#'       and the open-discovery channel -- see \code{cultivar_evidence_source}
#'       to tell them apart.}
#'     \item{cultivar_evidence_source}{For \code{prior_source_type ==
#'       "domestic_plant"} rows only (\code{NA} otherwise): \code{"known_list"}
#'       (matched \code{known_cultivar_taxa}, patched without needing local
#'       evidence), \code{"candidate_supplied"} (from \code{candidate_plant_taxa},
#'       required and found real local evidence), or \code{"inat_confirmed"}
#'       (from the automatic open-discovery residual step, required and found
#'       real local evidence).}
#'     \item{inat_n_observations_local}{Raw local iNaturalist observation
#'       count backing this row (audit column, mirrors
#'       \code{generate_undetected_diversity()}'s \code{source_taxon_name}
#'       pattern). \code{NA} for a request failure OR when a kingdom mismatch
#'       (see \code{inat_kingdom_mismatch}) discarded the evidence.}
#'     \item{inat_kingdom}{iNaturalist's own resolved kingdom for the matched
#'       taxon (via \code{TaxaFetch::fetch_inat_occurrences()}'s
#'       \code{inat_kingdom}). \code{NA} when the taxon wasn't found on iNaturalist.}
#'     \item{inat_kingdom_mismatch}{Logical. \code{TRUE} when \code{taxonomy}
#'       supplied a kingdom for this taxon that disagrees with
#'       \code{inat_kingdom} -- iNaturalist resolves names against its own
#'       curated taxonomy, not NCBI's or GBIF's, so a name can occasionally
#'       match an unrelated homonym in a different kingdom. When this fires,
#'       the local-evidence boost is discarded (treated the same as no local
#'       evidence) rather than trusted -- the candidate still gets patched
#'       normally if it's on a fixed list; only the extra confidence from a
#'       (likely wrong) local match is dropped. \code{FALSE} when no mismatch
#'       is detected (including when it can't be checked at all, e.g. no
#'       \code{taxonomy} kingdom column supplied).}
#'   }
#'   plus \code{<habitat_col>} (NA) when \code{model_obj} has one, and
#'   taxonomy rank columns when \code{taxonomy} is supplied.
#'
#' @seealso \code{\link{generate_undetected_diversity}},
#'   \code{TaxaFetch::fetch_inat_occurrences()},
#'   \code{TaxaFlag::add_posthoc_assessment()} (the downstream categorical
#'   re-labelling this complements).
#'
#' @examples
#' \dontrun{
#' domestic_food <- generate_domestic_food_priors(
#'   model_fit, lat = 34.41, lng = -119.86, grid_id = "Grid_34p4_m119p9"
#' )
#' taxaexpect_priors <- dplyr::bind_rows(taxaexpect_priors, domestic_food)
#' }
#'
#' @importFrom dplyr mutate bind_rows left_join
#' @importFrom tibble tibble
#' @export
generate_domestic_food_priors <- function(
    model_obj,
    lat,
    lng,
    grid_id              = NA_character_,
    domestic_animal_taxa = .default_domestic_animal_taxa,
    food_species_taxa    = .default_food_species_taxa,
    known_cultivar_taxa  = .default_known_cultivar_taxa,
    candidate_plant_taxa  = NULL,
    match_list_taxa       = NULL,
    taxaexpect_priors     = NULL,
    radius_km            = 50,
    ess                   = 5,
    max_ess               = 50,
    taxonomy              = NULL,
    api_token             = Sys.getenv("INAT_API_TOKEN"),
    verbose               = FALSE
) {
  if (!inherits(model_obj, "biofreq_model")) {
    stop("generate_domestic_food_priors: model_obj must be a biofreq_model ",
         "object from train_biodiversity_model().")
  }
  if (!is.numeric(lat) || length(lat) != 1L || is.na(lat)) {
    stop("generate_domestic_food_priors: `lat` must be a single non-NA numeric value.")
  }
  if (!is.numeric(lng) || length(lng) != 1L || is.na(lng)) {
    stop("generate_domestic_food_priors: `lng` must be a single non-NA numeric value.")
  }
  if (!requireNamespace("TaxaTools", quietly = TRUE)) {
    stop("generate_domestic_food_priors: the TaxaTools package is required ",
         "(used to normalize candidate taxon names to this ecosystem's ",
         "binomial convention via clean_taxon_names()).")
  }

  N_total     <- model_obj$N_total
  habitat_col <- model_obj$meta$habitat_col

  if (N_total <= 0) {
    stop("generate_domestic_food_priors: N_total is zero or negative. ",
         "Check that train_biodiversity_model() ran successfully.")
  }

  beta_mean <- function(a, b) a / (a + b)
  beta_sd   <- function(a, b) sqrt((a * b) / ((a + b)^2 * (a + b + 1)))

  candidates <- dplyr::bind_rows(
    if (length(domestic_animal_taxa) > 0L) {
      tibble::tibble(taxon_name = unique(domestic_animal_taxa), prior_source_type = "domestic_animal",
                     requires_local_evidence = FALSE, cultivar_evidence_source = NA_character_)
    },
    if (length(food_species_taxa) > 0L) {
      tibble::tibble(taxon_name = unique(food_species_taxa), prior_source_type = "food_species",
                     requires_local_evidence = FALSE, cultivar_evidence_source = NA_character_)
    },
    if (length(known_cultivar_taxa) > 0L) {
      tibble::tibble(taxon_name = unique(known_cultivar_taxa), prior_source_type = "domestic_plant",
                     requires_local_evidence = FALSE, cultivar_evidence_source = "known_list")
    },
    if (!is.null(candidate_plant_taxa) && length(candidate_plant_taxa) > 0L) {
      tibble::tibble(taxon_name = unique(candidate_plant_taxa), prior_source_type = "domestic_plant",
                     requires_local_evidence = TRUE, cultivar_evidence_source = "candidate_supplied")
    }
  )

  if (nrow(candidates) > 0L) {
    # Normalize every candidate name (defaults AND user-supplied overrides)
    # through this ecosystem's standard cleaner before it becomes a join key.
    # clean_taxon_names() truncates to genus + epithet only (e.g. a subspecies
    # trinomial like "Sus scrofa domesticus" -> "Sus scrofa"), which is exactly
    # what happens to every match_obj$taxon_name value elsewhere in the
    # pipeline -- skipping this step here would leave an uncleaned trinomial
    # (or a hybrid-formula name like "Fragaria x ananassa") that can never
    # exact-match join_priors()'s taxon_name join.
    raw_names     <- candidates$taxon_name
    cleaned_names <- TaxaTools::clean_taxon_names(raw_names)
    dropped       <- unique(raw_names[is.na(cleaned_names)])
    if (length(dropped) > 0L) {
      warning(sprintf(
        "generate_domestic_food_priors: %d candidate name(s) could not be cleaned by TaxaTools::clean_taxon_names() and were dropped: %s",
        length(dropped), paste(dropped, collapse = ", ")
      ), call. = FALSE)
    }
    candidates$taxon_name <- cleaned_names
    candidates <- candidates[!is.na(candidates$taxon_name), ]
  }

  if (nrow(candidates) == 0L) {
    message("generate_domestic_food_priors: no candidate taxa supplied (all four fixed/supplied channels empty/NULL).")
    # dplyr::bind_rows() of all-empty/NULL inputs produces a zero-row,
    # zero-COLUMN tibble -- give it a real schema so candidates$taxon_name
    # (used below, both in the match-list gating and the main loop) doesn't
    # error with "unknown or uninitialised column" when match_list_taxa is
    # supplied but every fixed/supplied channel is empty.
    candidates <- tibble::tibble(
      taxon_name = character(0), prior_source_type = character(0),
      requires_local_evidence = logical(0), cultivar_evidence_source = character(0)
    )
  } else {
    # First occurrence wins if the same name appears in more than one channel
    # (e.g. a user accidentally lists a species in both domestic_animal_taxa
    # and food_species_taxa) -- domestic_animal takes priority over
    # food_species over known_cultivar_taxa over user-supplied
    # candidate_plant_taxa, matching the order rows were bound above. Also
    # collapses any duplicates created by cleaning (e.g. two distinct raw
    # entries that normalize to the same cleaned name).
    candidates <- candidates[!duplicated(candidates$taxon_name), ]
  }

  # ---------------------------------------------------------------------------
  # Match-list gating (opt-in via match_list_taxa) -- see @section Match-list
  # gating in the roxygen above for the full rationale. NULL preserves the
  # original behavior exactly: every fixed-list channel is checked in full,
  # with no gating and no open-discovery residual step.
  # ---------------------------------------------------------------------------
  if (!is.null(match_list_taxa) && length(match_list_taxa) > 0L) {
    match_set <- unique(stats::na.omit(TaxaTools::clean_taxon_names(match_list_taxa)))

    n_before   <- nrow(candidates)
    candidates <- candidates[candidates$taxon_name %in% match_set, ]
    message(sprintf(
      paste0(
        "generate_domestic_food_priors: match_list_taxa supplied -- restricted ",
        "%d fixed-list/supplied candidate(s) to %d actually present in the match list."
      ), n_before, nrow(candidates)
    ))

    # Residual: match-list taxa not already covered by a fixed list or a
    # user-supplied candidate, and not already carrying a named (modelled)
    # prior. This is the ONLY pool the open-discovery channel draws from --
    # deliberately not pre-restricted to known_cultivar_taxa or any other
    # list, since the whole point of a live check is to catch what nothing
    # anticipated.
    already_covered <- candidates$taxon_name
    if (!is.null(taxaexpect_priors)) {
      existing_taxa <- if (is.data.frame(taxaexpect_priors)) {
        taxaexpect_priors$taxon_name
      } else {
        taxaexpect_priors
      }
      already_covered <- c(already_covered, stats::na.omit(existing_taxa))
    }
    residual_pool <- setdiff(match_set, already_covered)

    if (length(residual_pool) > 0L) {
      has_phylum <- !is.null(taxonomy) && is.data.frame(taxonomy) &&
        all(c("taxon_name", "phylum") %in% names(taxonomy))
      if (!has_phylum) {
        message(sprintf(
          paste0(
            "generate_domestic_food_priors: %d match-list taxon/taxa remain ",
            "unreferenced after fixed-list/prior exclusion, but `taxonomy` was ",
            "not supplied with a 'phylum' column -- the open cultivated-plant ",
            "discovery step cannot be scoped safely and is skipped."
          ), length(residual_pool)
        ))
      } else {
        phylum_lookup <- stats::setNames(taxonomy$phylum, taxonomy$taxon_name)
        phylum_lookup <- phylum_lookup[!duplicated(names(phylum_lookup))]
        residual_phylum <- unname(phylum_lookup[residual_pool])
        # Both spellings needed: TaxaMatch::convert_taxonomy_backbone()'s
        # per-column NCBI fallback means a real dataset can legitimately
        # carry either "Streptophyta" (NCBI-style) or "Tracheophyta"
        # (GBIF-backbone-style) for land plants, sometimes both at once.
        residual_scoped <- residual_pool[!is.na(residual_phylum) &
                                          residual_phylum %in% c("Streptophyta", "Tracheophyta")]
        message(sprintf(
          paste0(
            "generate_domestic_food_priors: %d unreferenced match-list taxon/taxa; ",
            "%d fall in a plausibly-cultivable phylum (Streptophyta/Tracheophyta) ",
            "and will be checked against iNaturalist for real local cultivated evidence."
          ), length(residual_pool), length(residual_scoped)
        ))
        if (length(residual_scoped) > 0L) {
          candidates <- dplyr::bind_rows(
            candidates,
            tibble::tibble(
              taxon_name = residual_scoped, prior_source_type = "domestic_plant",
              requires_local_evidence = TRUE, cultivar_evidence_source = "inat_confirmed"
            )
          )
        }
      }
    }
  }

  # Kingdom lookup for the iNaturalist cross-check -- built early (before the
  # loop) so each candidate's own kingdom is available at check time. Only
  # active when `taxonomy` supplies a `kingdom` column; otherwise a mismatch
  # simply can't be detected and every iNaturalist result is trusted as-is,
  # same as before this check existed.
  kingdom_lookup <- NULL
  if (!is.null(taxonomy) && is.data.frame(taxonomy) &&
      all(c("taxon_name", "kingdom") %in% names(taxonomy))) {
    kingdom_lookup <- stats::setNames(taxonomy$kingdom, taxonomy$taxon_name)
    kingdom_lookup <- kingdom_lookup[!duplicated(names(kingdom_lookup))]
  }

  proxy_rows <- vector("list", nrow(candidates))

  if (nrow(candidates) > 0L) {
    message(sprintf("Checking %d domestic/food/plant candidate(s) against iNaturalist...", nrow(candidates)))

    for (i in seq_len(nrow(candidates))) {
      row      <- candidates[i, ]
      category <- row$prior_source_type
      if (verbose) message(sprintf("[%d/%d] %s (%s)", i, nrow(candidates), row$taxon_name, category))

      inat_out <- tryCatch(
        TaxaFetch::fetch_inat_occurrences(
          taxon_names   = row$taxon_name,
          lat           = lat,
          lng           = lng,
          radius_km     = radius_km,
          captive       = "any",
          quality_grade = if (category == "domestic_plant") "casual" else "any",
          api_token     = api_token,
          verbose       = FALSE
        ),
        error = function(e) {
          warning(sprintf(
            "generate_domestic_food_priors: iNaturalist lookup failed for '%s': %s",
            row$taxon_name, conditionMessage(e)
          ), call. = FALSE)
          NULL
        }
      )

      n_local      <- if (is.null(inat_out)) NA_integer_ else inat_out$n_observations_local[[1]]
      inat_kingdom <- if (is.null(inat_out)) NA_character_ else inat_out$inat_kingdom[[1]]

      # iNaturalist resolves names against its own curated taxonomy, not
      # NCBI's or GBIF's -- a name can occasionally match an unrelated
      # homonym in a different kingdom. When we know the candidate's real
      # kingdom (via `taxonomy`) and it disagrees with what iNaturalist
      # returned, discard the local-evidence boost rather than trust a
      # possible wrong-organism match. This never removes a fixed-list
      # category itself -- only the extra confidence a (likely wrong) local
      # hit would have added.
      known_kingdom <- if (is.null(kingdom_lookup)) {
        NA_character_
      } else {
        unname(kingdom_lookup[row$taxon_name])  # single-bracket: NA for an unmatched name, not an error
      }
      kingdom_mismatch <- !is.na(known_kingdom) && !is.na(inat_kingdom) &&
        !identical(known_kingdom, inat_kingdom)
      if (isTRUE(kingdom_mismatch)) {
        warning(sprintf(
          paste0(
            "generate_domestic_food_priors: iNaturalist match for '%s' resolved ",
            "to kingdom '%s', but the supplied taxonomy says '%s' -- likely a ",
            "homonym in a different kingdom. Discarding the local-evidence boost."
          ),
          row$taxon_name, inat_kingdom, known_kingdom
        ), call. = FALSE)
        n_local <- NA_integer_
      }

      if (isTRUE(row$requires_local_evidence) && (is.na(n_local) || n_local <= 0L)) {
        # candidate_plant_taxa entries and open-discovery residual entries
        # (cultivar_evidence_source "candidate_supplied"/"inat_confirmed")
        # require real local evidence -- without it there is no basis to
        # assume presence, so this candidate is skipped entirely rather than
        # given a floor prior. known_cultivar_taxa/domestic_animal_taxa/
        # food_species_taxa entries never reach here regardless of n_local,
        # since requires_local_evidence is FALSE for all three.
        proxy_rows[[i]] <- NULL
        next
      }

      evidence_ess <- if (is.na(n_local) || n_local <= 0L) {
        ess
      } else {
        min(max_ess, max(ess, log1p(n_local)))
      }

      alpha_i <- min(evidence_ess, N_total - 1)
      beta_i  <- N_total - alpha_i

      proxy_tbl <- tibble::tibble(
        taxon_name                = row$taxon_name,
        grid_id                   = grid_id,
        alpha                     = alpha_i,
        beta                      = beta_i,
        theta_mean                = beta_mean(alpha_i, beta_i),
        theta_sd                  = beta_sd(alpha_i, beta_i),
        model_tier                = "tier_domestic_food",
        prior_source_type         = category,
        cultivar_evidence_source  = row$cultivar_evidence_source,
        inat_n_observations_local = n_local,
        inat_kingdom              = inat_kingdom,
        inat_kingdom_mismatch     = isTRUE(kingdom_mismatch)
      )
      if (!is.null(habitat_col)) {
        proxy_tbl[[habitat_col]] <- NA_character_
      }
      proxy_rows[[i]] <- proxy_tbl
    }
  }

  proxy_list <- Filter(Negate(is.null), proxy_rows)

  if (length(proxy_list) == 0L) {
    message("generate_domestic_food_priors: no candidates produced a prior row.")
    result <- tibble::tibble(
      taxon_name                = character(0),
      grid_id                   = character(0),
      alpha                     = numeric(0),
      beta                      = numeric(0),
      theta_mean                = numeric(0),
      theta_sd                  = numeric(0),
      model_tier                = character(0),
      prior_source_type         = character(0),
      cultivar_evidence_source  = character(0),
      inat_n_observations_local = integer(0),
      inat_kingdom              = character(0),
      inat_kingdom_mismatch     = logical(0)
    )
    if (!is.null(habitat_col)) result[[habitat_col]] <- character(0)
  } else {
    result <- dplyr::bind_rows(proxy_list)
  }

  tax_rank_cols <- c("genus", "family", "order", "class", "phylum")
  if (!is.null(taxonomy)) {
    if (!is.data.frame(taxonomy) || !"taxon_name" %in% names(taxonomy)) {
      stop("generate_domestic_food_priors: taxonomy must be a data frame with a 'taxon_name' column.")
    }
    tax_cols_present <- intersect(tax_rank_cols, names(taxonomy))
    if (length(tax_cols_present) == 0L) {
      warning("generate_domestic_food_priors: taxonomy has none of genus/family/order/class/phylum -- ignored.")
    } else {
      tax_lookup <- unique(taxonomy[, c("taxon_name", tax_cols_present), drop = FALSE])
      tax_lookup <- tax_lookup[!duplicated(tax_lookup$taxon_name), ]
      result <- dplyr::left_join(result, tax_lookup, by = "taxon_name")
    }
  }
  for (.col in tax_rank_cols) {
    if (!.col %in% names(result)) result[[.col]] <- NA_character_
  }

  message(sprintf(
    "--- Domestic/food priors complete: %d row(s) (%d checked) ---",
    nrow(result), nrow(candidates)
  ))

  result
}
