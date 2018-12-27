---
layout: post
title: >
  O código mais "bonito" que já escrevi f'#{self.ego}'
---

Inspirado pelo projeto [AlphaGo](https://deepmind.com/blog/alphago-zero-learning-scratch/), um projeto que aprende a jogar Go sozinho usando _machine learning_, decidi criar um projeto semelhante, e o jogo escolhido foi... _O jogo da velha_!

![hein?](/public/2018-07-22-o-codigo-mais-bonito-que-ja-escrevi/old-lady.jpg){: .center }

Pois é…

### O código

Antes de tudo eu precisava de uma grande quantidade de partidas para treinar a rede neural. Para isso, criei um pequeno _script_ que gera jogas aleatórias com seus respectivos passos e resultado, eis o tal código:

```python
def run():
    board = np.zeros((3, 3), dtype=np.int)
    players = np.array([1, 2])
    np.random.shuffle(players)
    player, next_player = players[:]

    while True:
        sys.stdout.write('\n')
        sys.stdout.write(str(player))
        sys.stdout.write(''.join(map(str, board.flatten())))

        slots = (board == 0).flatten()
        available_slots = np.where(slots == True)[0]
        if available_slots.size == 0:
            sys.stdout.write('3')
            break

        mask = board == player
        out = mask.all(0).any() | mask.all(1).any()
        out |= np.diag(mask).all() | np.diag(mask[:, ::-1]).all()
        if out:
            sys.stdout.write(str(player))
            break

        sys.stdout.write('0')

        picked = np.random.choice(available_slots)
        board[picked / 3][picked % 3] = player
        next_player, player = player, next_player
```

### Passo a passo

```python
board = np.zeros((3, 3), dtype=np.int)  # Cria um "tabuleiro" 3x3 inicializado com zero.
players = np.array([1, 2])  # Cria os jogadores.
np.random.shuffle(players)  # Embaralha os jogadores.
player, next_player = players[:]  # Após embaralhar, separamos os jogadores já sorteados.
```

```python
sys.stdout.write(str(player))  # Imprime quem está jogando.
sys.stdout.write(''.join(map(str, board.flatten())))  # Imprime o estado atual do tabuleiro.
```

```python
# Filtra pelas posições livres do tabuleiro.
slots = (board == 0).flatten()
available_slots = np.where(slots == True)[0]

# Caso não haja nenhuma posição livre, declara empate e termina o `loop`.
if available_slots.size == 0:
    sys.stdout.write('3')
    break
```

```python
# Esse trecho é um pouco mais complexo, e graças ao numpy
# a verificação do jogador vitoriosos é mais simplificada.

# Cria uma máscara em relação o jogador atual e o tabuleiro.
mask = board == player

# Verifica a condição de vitória na horizontal e/ou vertical.
out = mask.all(0).any() | mask.all(1).any()

# Verifica a condição de vitória na diagonal.
out |= np.diag(mask).all() | np.diag(mask[:, ::-1]).all()

# Caso haja uma condição que satisfaça a vitória, imprime o jogador vitorioso.
if out:
    sys.stdout.write(str(player))
    break
```

```python
# Ninguém ganhou, o jogo continua.
sys.stdout.write('0')
```

```python
# Escolhe uma posição do tabuleiro que esteja livre.
picked = np.random.choice(available_slots)

# Atribui o número do jogador ao lugar do tabuleiro sorteado.
board[picked / 3][picked % 3] = player

# Troca quem joga na próxima interação.
next_player, player = player, next_player
```

### A saída

O _script_ escreve na saída `stdout` o resultado de cada interação, o formato de saída é este:

```
PTTTTTTTTTR
```

* `P` - Representa o jogador, sendo **1** ou **2**.
* `T` - Indica o estado de cada posição do tabuleiro, **0** caso esteja livre; **1** ou **2*** caso esteja preenchido.
* `R` - Indica o resultado,  **0** caso ainda não haja uma vitória, **3** caso seja um empate ou **1** ou **2** caso um dos jogadores tenha vencido.

### A partida

```shell
$ python generator.py

10000000000
20020000000
10021000000
20021200000
10021200100
20221200100
10221201100
20221201120
11221201121
```

No caso acima, o jogador  **1** iniciou a partida e acabou sendo o vitorioso. Vejamos outra partida:

```shell
$ python generator.py

20000000000
10000100000
20000120000
10000121000
20002121000
11002121000
21202121000
11202121100
21222121100
11222121113
```

Nessa partida o jogador **2** começou e terminou em empate.

### Próximos passos

Não sei bem ao certo se irei usar [deep reinforcement learning (deep Q-learning)](https://keon.io/deep-q-learning/) #recomendo ou algum outro método para este projeto, fiquem atentos aos próximos capítulos.
