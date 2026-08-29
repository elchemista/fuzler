defmodule FuzlerCorpusTest do
  use ExUnit.Case, async: true

  @equivalent_names [
    {"name: Mario Rossi", "Mario Rossi", "mario rossi"},
    {"name: Anna Bianchi", "ANNA BIANCHI", "anna bianchi"},
    {"name: Luca Ferrari", "Luca-Ferrari", "luca ferrari"},
    {"name: Giulia Romano", "Giulia, Romano", "giulia romano"},
    {"name: Marco Esposito", "  Marco   Esposito  ", "marco esposito"},
    {"name: Siobhán O'Connor", "SIOBHÁN O'CONNOR", "siobhán o connor"},
    {"name: Jean-Luc Picard", "Jean-Luc Picard", "jean luc picard"},
    {"name: José García", "JOSÉ GARCÍA", "josé garcía"},
    {"name: François Dupont", "FRANÇOIS DUPONT", "françois dupont"},
    {"name: Jürgen Müller", "JÜRGEN MÜLLER", "jürgen müller"},
    {"name: Søren Kierkegaard", "SØREN KIERKEGAARD", "søren kierkegaard"},
    {"name: Björk Guðmundsdóttir", "BJÖRK GUÐMUNDSDÓTTIR", "björk guðmundsdóttir"},
    {"name: Łukasz Żółć", "ŁUKASZ ŻÓŁĆ", "łukasz żółć"},
    {"name: Chloë Moreau", "CHLOË MOREAU", "chloë moreau"},
    {"name: Zoë Kravitz", "ZOË KRAVITZ", "zoë kravitz"},
    {"name: Renée Zellweger", "RENÉE ZELLWEGER", "renée zellweger"},
    {"name: André Silva", "ANDRÉ SILVA", "andré silva"},
    {"name: Maëlle Martin", "MAËLLE MARTIN", "maëlle martin"},
    {"name: Antonín Dvořák", "ANTONÍN DVOŘÁK", "antonín dvořák"},
    {"name: Iñigo Núñez", "IÑIGO NÚÑEZ", "iñigo núñez"},
    {"name: João Silva", "JOÃO SILVA", "joão silva"},
    {"name: María-José López", "María-José López", "maría josé lópez"},
    {"name: Ada Lovelace", "Dr. Ada Lovelace", "dr ada lovelace"},
    {"name: Grace Hopper", "Grace\tHopper", "grace hopper"},
    {"name: Alan Turing", "Alan\nTuring", "alan turing"}
  ]

  @equivalent_cities [
    {"city: New York", "New-York", "new york"},
    {"city: Los Angeles", "LOS ANGELES", "los angeles"},
    {"city: São Paulo", "SÃO PAULO", "são paulo"},
    {"city: Rio de Janeiro", "Rio_de_Janeiro", "rio de janeiro"},
    {"city: Mexico City", "MEXICO CITY", "mexico city"},
    {"city: Buenos Aires", "Buenos   Aires", "buenos aires"},
    {"city: San Francisco", "San Francisco!", "san francisco"},
    {"city: Ho Chi Minh City", "HO CHI MINH CITY", "ho chi minh city"},
    {"city: St Louis", "St. Louis", "st louis"},
    {"city: Washington DC", "Washington, D.C.", "washington d c"},
    {"city: Reggio nell Emilia", "Reggio nell'Emilia", "reggio nell emilia"},
    {"city: Castellammare di Stabia", "Castellammare-di-Stabia", "castellammare di stabia"},
    {"city: Frankfurt am Main", "FRANKFURT AM MAIN", "frankfurt am main"},
    {"city: Aix en Provence", "Aix-en-Provence", "aix en provence"},
    {"city: Santiago de Chile", "Santiago/de/Chile", "santiago de chile"},
    {"city: Ciudad de México", "CIUDAD DE MÉXICO", "ciudad de méxico"},
    {"city: Kraków", "KRAKÓW", "kraków"},
    {"city: Zürich", "ZÜRICH", "zürich"},
    {"city: München", "MÜNCHEN", "münchen"},
    {"city: København", "KØBENHAVN", "københavn"},
    {"city: Göteborg", "GÖTEBORG", "göteborg"},
    {"city: Beijing", "Beijing...", "beijing"},
    {"city: Tokyo", "  TOKYO  ", "tokyo"},
    {"city: Cape Town", "Cape\tTown", "cape town"},
    {"city: Abu Dhabi", "Abu\nDhabi", "abu dhabi"}
  ]

  @equivalent_mixed [
    {"phrase: greeting", "Buongiorno, mondo!", "buongiorno mondo"},
    {"phrase: weather", "Oggi-c'è-il-sole", "oggi c è il sole"},
    {"phrase: appointment", "Appuntamento: domani alle 9", "appuntamento domani alle 9"},
    {"phrase: question", "Come stai? Tutto bene?", "come stai tutto bene"},
    {"phrase: whitespace", "Una\tfrase\ncon  spazi", "una frase con spazi"},
    {"mixed: software version", "Version 2.0 released", "version 2 0 released"},
    {"mixed: order number", "Order #12345 ready", "order 12345 ready"},
    {"mixed: email", "user@example.com", "user example com"},
    {"mixed: IPv4 address", "192.168.1.1", "192 168 1 1"},
    {"mixed: ISBN", "ISBN: 978-1-4028-9462-6", "isbn 978 1 4028 9462 6"},
    {"mixed: street address", "Via Roma, 10", "via roma 10"},
    {"mixed: programming languages", "C++ and Rust", "c and rust"},
    {"mixed: BEAM languages", "Elixir/Erlang", "elixir erlang"},
    {"mixed: date", "29/08/2026", "29 08 2026"},
    {"mixed: percentage", "50% discount", "50 discount"},
    {"mixed: currency", "Price: € 19.99", "price 19 99"},
    {"mixed: product code", "ABC-123-XYZ", "abc 123 xyz"},
    {"mixed: phone number", "+39 (02) 1234-5678", "39 02 1234 5678"},
    {"mixed: hashtag", "#ElixirLang", "elixirlang"},
    {"mixed: mention", "@open_source", "open source"},
    {"mixed: emoji separators", "hello 👋 world", "hello world"},
    {"mixed: mathematical separators", "alpha + beta = gamma", "alpha beta gamma"},
    {"mixed: file path", "lib/fuzler/native.ex", "lib fuzler native ex"},
    {"mixed: UUID", "550e8400-e29b-41d4-a716-446655440000",
     "550e8400 e29b 41d4 a716 446655440000"},
    {"mixed: punctuation only", "--- !!!", ""}
  ]

  @typo_cases [
    {"typo: Mario", "mario", "marco"},
    {"typo: Giulia", "giulia", "giula"},
    {"typo: Francesca", "francesca", "francseca"},
    {"typo: Alessandro", "alessandro", "alessanrdo"},
    {"typo: Beatrice", "beatrice", "beatrce"},
    {"typo: Lorenzo", "lorenzo", "lorenso"},
    {"typo: Valentina", "valentina", "valentna"},
    {"typo: Emanuele", "emanuele", "emmanuele"},
    {"typo: Caterina", "caterina", "catrina"},
    {"typo: Riccardo", "riccardo", "ricardo"},
    {"typo: Amsterdam", "amsterdam", "amsterdm"},
    {"typo: Barcelona", "barcelona", "barcelon"},
    {"typo: Lisbon", "lisbon", "lisbn"},
    {"typo: Florence", "florence", "florance"},
    {"typo: Venice", "venice", "venic"},
    {"typo: Palermo", "palermo", "palrmo"},
    {"typo: Bologna", "bologna", "bolonga"},
    {"typo: Napoli", "napoli", "napli"},
    {"typo: Milano", "milano", "milno"},
    {"typo: London", "london", "londom"},
    {"typo: Berlin", "berlin", "berln"},
    {"typo: Madrid", "madrid", "madrd"},
    {"typo: Dublin", "dublin", "dubln"},
    {"typo: Prague", "prague", "prage"},
    {"typo: Vienna", "vienna", "viena"}
  ]

  @partial_cases [
    {"partial: person in sentence", "Mario Rossi",
     "ieri ho incontrato Mario Rossi alla stazione"},
    {"partial: accented person", "José García", "il relatore José García aprirà la conferenza"},
    {"partial: hyphenated person", "Jean-Luc Picard", "il capitano Jean Luc Picard salì a bordo"},
    {"partial: city New York", "New York", "il prossimo volo diretto arriva a New York domani"},
    {"partial: city São Paulo", "São Paulo", "la società ha aperto un ufficio a São Paulo"},
    {"partial: city Cape Town", "Cape Town", "trascorreremo una settimana intera a Cape Town"},
    {"partial: Italian greeting", "buongiorno a tutti",
     "il presentatore disse buongiorno a tutti e iniziò"},
    {"partial: English greeting", "good morning", "she smiled and said good morning to everyone"},
    {"partial: Spanish greeting", "buenos días", "al entrar saludò con buenos días a todos"},
    {"partial: French greeting", "bonjour tout le monde",
     "il messaggio iniziava con bonjour tout le monde ieri"},
    {"partial: appointment", "domani alle nove",
     "la riunione è confermata per domani alle nove in ufficio"},
    {"partial: release phrase", "version 2 released",
     "the changelog says version 2 released after testing"},
    {"partial: order code", "order 12345",
     "customer support confirmed that order 12345 is ready"},
    {"partial: street address", "via roma 10",
     "la consegna deve arrivare in via roma 10 entro sera"},
    {"partial: product code", "abc 123 xyz",
     "search the catalogue for product abc 123 xyz today"},
    {"partial: weather phrase", "piove molto", "secondo le previsioni oggi piove molto in città"},
    {"partial: travel phrase", "treno per Milano",
     "stiamo aspettando il treno per Milano al binario cinque"},
    {"partial: food phrase", "pizza margherita",
     "per cena abbiamo ordinato una pizza margherita grande"},
    {"partial: support phrase", "password dimenticata",
     "seleziona il collegamento password dimenticata nella pagina"},
    {"partial: system phrase", "errore di connessione",
     "il registro mostra un errore di connessione intermittente"},
    {"partial: numeric phrase", "invoice 2026 08",
     "please archive invoice 2026 08 after payment"},
    {"partial: email tokens", "user example com",
     "send the report to user example com before noon"},
    {"partial: programming phrase", "Elixir and Rust",
     "this library combines Elixir and Rust for speed"},
    {"partial: book phrase", "the old man", "the title begins with the old man and continues"},
    {"partial: short identifier", "550e8400", "the request identifier is 550e8400 in the log"}
  ]

  @unrelated_cases [
    {"unrelated: person and science", "Mario Rossi", "quantum particle accelerator"},
    {"unrelated: person and weather", "Anna Bianchi", "tropical thunderstorm warning"},
    {"unrelated: person and cooking", "Luca Ferrari", "roasted pumpkin soup"},
    {"unrelated: person and hardware", "Giulia Romano", "wireless mechanical keyboard"},
    {"unrelated: person and finance", "Marco Esposito", "quarterly revenue forecast"},
    {"unrelated: New York and food", "New York", "homemade vegetable lasagna"},
    {"unrelated: São Paulo and astronomy", "São Paulo", "distant spiral galaxy"},
    {"unrelated: Cape Town and software", "Cape Town", "distributed database cluster"},
    {"unrelated: Tokyo and nature", "Tokyo station", "ancient mountain forest"},
    {"unrelated: Zürich and sport", "Zürich centre", "professional basketball tournament"},
    {"unrelated: greeting and database", "buongiorno a tutti", "postgres replication slot"},
    {"unrelated: appointment and music", "domani alle nove", "electric guitar amplifier"},
    {"unrelated: weather and security", "oggi splende il sole", "encrypted authentication token"},
    {"unrelated: travel and medicine", "treno per Milano", "clinical blood pressure"},
    {"unrelated: food and networking", "pizza margherita", "ethernet routing protocol"},
    {"unrelated: support and gardening", "password dimenticata", "organic tomato seedlings"},
    {"unrelated: connection and history", "errore di connessione", "medieval European castle"},
    {"unrelated: release and biology", "version 2 released", "marine mammal migration"},
    {"unrelated: order and geology", "order 12345 ready", "volcanic rock formation"},
    {"unrelated: address and cinema", "via roma 10", "independent documentary film"},
    {"unrelated: email and agriculture", "user example com", "winter wheat harvest"},
    {"unrelated: product and philosophy", "abc 123 xyz", "existential moral philosophy"},
    {"unrelated: invoice and ocean", "invoice 2026 08", "deep ocean current"},
    {"unrelated: programming and dance", "Elixir and Rust", "classical ballet performance"},
    {"unrelated: identifier and language", "550e8400 e29b", "ancient Sanskrit grammar"}
  ]

  @equivalent_cases @equivalent_names ++ @equivalent_cities ++ @equivalent_mixed
  @corpus_size length(@equivalent_cases) + length(@typo_cases) + length(@partial_cases) +
                 length(@unrelated_cases)

  test "the behavioural corpus contains at least 100 explicit examples" do
    assert @corpus_size == 150
  end

  for {label, left, right} <- @equivalent_cases do
    test "normalisation equivalence - #{label}" do
      assert Fuzler.similarity_score(unquote(left), unquote(right)) == 1.0
    end
  end

  for {label, left, right} <- @typo_cases do
    test "typo tolerance - #{label}" do
      score = Fuzler.similarity_score(unquote(left), unquote(right))

      assert score >= 0.7
      assert score < 1.0
    end
  end

  for {label, query, target} <- @partial_cases do
    test "contained phrase - #{label}" do
      score = Fuzler.similarity_score(unquote(query), unquote(target))

      assert score > 0.5
      assert score < 1.0
    end
  end

  for {label, left, right} <- @unrelated_cases do
    test "unrelated text - #{label}" do
      assert Fuzler.similarity_score(unquote(left), unquote(right)) <= 0.4
    end
  end
end
