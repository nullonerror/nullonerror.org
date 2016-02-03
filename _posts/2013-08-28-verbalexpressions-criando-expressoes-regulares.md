---
layout: post
title: >
  Criando expressões regulares de uma maneira fácil
---

Recentemente encontrei um projeto muito bacana chamado [VerbalExpressions](https://github.com/VerbalExpressions/) que usa e abusa de _fluent interfaces_ para construir expressões regulares, como é possivel notar, essa ideia já foi portada para diversas linguagens!

E como já existia um port para [Python](https://github.com/VerbalExpressions/PythonVerbalExpressions) e para [C++](https://github.com/VerbalExpressions/CppVerbalExpressions), decidi "portar" para [Qt](http://qt-project.org/). Na verdade portar entre aspas, pois meu trabalho se resumiu a _"s/std::string/QString/g"_ fora outras pequenas mudanças e/ou otimizações, logo, os creditos são todos do autor do [CppVerbalExpressions](https://github.com/VerbalExpressions/CppVerbalExpressions)

Construir expressões regulares nem sempre é uma tarefa simples, exceto para aqueles que já leram o livro [Expressões Regulares - Uma abordagem divertida](http://aurelio.net/regex/), nesse caso ignore, pois você já está fera nisso ;)

Usando [fluent inteterface](http://en.wikipedia.org/wiki/Fluent_interface) esta árdua tarefa se resume numa versão "poética", como veremos a seguir:

``` cpp
auto expression = QVerbalExpressions()
  .searchOneLine()
  .startOfLine()
  .then("http")
  .maybe("s")
  .then("://")
  .maybe("www.")
  .anythingBut(" ")
  .endOfLine();

qDebug() << expression; // ^(?:http)(?:s)?(?:://)(?:www.)?(?:[^ ]*)$
qDebug() << expression.test("https://www.google.com"); // true
```

Que resulta na seguinte expressão `^(?:http)(?:s)?(?:://)(?:www.)?(?:[^ ]*)$`, legal né?

O código fonte se encontra em [QtVerbalExpressions](https://github.com/VerbalExpressions/QtVerbalExpressions).
