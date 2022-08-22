---
layout: post
title: >
  O if mais rápido do velho oeste
---

![image](/public/2015-03-31-o-if-mais-rapido-do-velho-oeste/sonic.png){: .center }

Provavelmente já deve ter se deparado com algum código semelhante a este, principalmente no kernel do Linux:

` if (unlikely(foo)) { ...`

ou

` if (likely(bar)) { ...`

E deve ter se perguntado o que seria esse _likely/unlikely_. Pesquisando mais a fundo vai descobrir que se trata de uma macro para dar uma dica ao processador que aquela condição tem mais chances de ser verdadeira ou falsa, permitindo assim ao processador já se antecipar e carregar os dados no cache da condição que tem mais probabilidade de estar correta.

O nome desse recurso é _branch prediction_ e existe um excelente (e obrigatório) _paper_ que fala sobre isso: [What Every Programmer Should Know About Memory](http://www.akkadia.org/drepper/cpumemory.pdf)

No Qt também temos algo semelhante, conhecidos por [Q_LIKELY](http://doc.qt.io/qt-5/qtglobal.html#Q_LIKELY) e [Q_UNLIKELY](http://doc.qt.io/qt-5/qtglobal.html#Q_UNLIKELY) que fazem praticamente a mesma coisa.

Ambos os conjutos são definidos com uma macro, usando a função [\_\_builtin_expect](https://gcc.gnu.org/onlinedocs/gcc/Other-Builtins.html), desta maneira:

```
#define likely(x)       __builtin_expect(!!(x), 1)
#define unlikely(x)     __builtin_expect(!!(x), 0)
```
