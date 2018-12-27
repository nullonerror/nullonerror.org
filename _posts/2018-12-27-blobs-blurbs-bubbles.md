---
layout: post
title: >
  Blobs, blurbs, bubbles…
---

> TL;DR Usar o SQLite ao invés do sistema de arquivos para armazenar em forma de blob os assets do jogo pode ser uma ótima ideia.

Dia desses estava lendo [SQLite As An Application File Format](https://www.sqlite.org/appfileformat.html) o que me fez lembrar de quando eu lia muito a respeito de desenvolvimento de jogos, até cheguei a desenvolver um framework chamado [Wintermoon](http://wintermoon.sourceforge.net/), no meu framework eu usei o [PhysicsFS](https://icculus.org/physfs/) foi quando descobri o [MPQ](http://www.zezula.net/en/mpq/main.html) e fiquei encantado.

## Mo'PaQ
O MPQ é (ou era) amplamente utilizado em praticamente todos os jogos da Blizzard, desde o Diablo (1997) até o StarCraft 2 (2010). Inclusive o StarCraft 2 recebe atualizações até hoje, e quase que mensalmente desde seu lançamento! Digo isto para dar um contexto de onde quero chegar.

O MPQ leva o nome de seu criador, e surgiu devido há alguns requerimentos da época, como segurança, acesso rápido, compressão, expansibilidade e multi-linguagem.

Atualmente alguns requerimentos mencionados não fazem muito sentido, porém estamos falando de uma época onde o principal sistema de arquivos onde esses títulos rodavam era o [FAT32](https://en.wikipedia.org/wiki/FAT32).

### PhysicsFS

Sempre gostei da ideia de empacotar os `assets` do jogo num único arquivo comprimido. O [PhysicsFS](https://icculus.org/physfs/) permite “montar” diretórios e arquivos comprimidos como se fossem um único diretório, com todos os arquivos estruturados dentro dos seus respectivos diretórios; algo semelhante ao que o [UnionFS](http://unionfs.filesystems.org/), [OverlayFS](https://www.kernel.org/doc/Documentation/filesystems/overlayfs.txt) e similares fazem.

Outra vantagem é a _segurança_, pois o processo fica restrito restrito à aquele(s) diretório(s) previamente _especificado(s)_.

Usar o `physfs` com a [SDL](https://www.libsdl.org/) é bem simples, veja como é o processo de montar um arquivo comprimido e carregar uma imagem:

```cpp
int main(int argc, char *argv[]) {
  PHYSFS_init(argv[0]);

  SDL_Init(SDL_INIT_VIDEO);

  // monta o arquivo `assets.7z` como se fosse um diretório.
  PHYSFS_mount("assets.7z", "/", 0);

  SDL_Window * window = SDL_CreateWindow(
    NULL, SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, 640, 480, SDL_WINDOW_OPENGL | SDL_WINDOW_ALLOW_HIGHDPI);

  SDL_Renderer * renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED);

  // carrega o arquivo `texture001.tga` que está dentro de `assets.7z`.
  SDL_RWops * rwops = PHYSFSRWOPS_openRead("texture001.tga");

  // carrega a textura.
  SDL_Surface * surface = IMG_Load_RW(rwops, 1);
  SDL_Texture * texture = SDL_CreateTextureFromSurface(renderer, surface);
  SDL_FreeSurface(surface);

  SDL_bool running = SDL_TRUE;
  while(running) {
    SDL_Event event;
    while (SDL_PollEvent(&event)) {
      if (event.type == SDL_QUIT) {
        running = SDL_FALSE;
      }
    }

    // desenha a textura na janela.
    SDL_RenderCopy(renderer, texture, NULL, NULL);
    SDL_RenderPresent(renderer);
    SDL_Delay(1000 / 60);
  }

  SDL_DestroyWindow(window);
  SDL_Quit();
  return 0;
}
```

Legal né?

### [Little Bobby Tables](https://xkcd.com/327/)

O [SQLite](https://www.sqlite.org/index.html) é provavelmente um dos componentes de software mais utilizados no mundo, está presente em todo o lugar; se estiver lendo esse texto num Android deve ter pelo menos umas 3 cópias dele na suas mãos! SQLite é como um `fopen(3)` com esteroides.

Lendo o texto que menciono no inicio do texto, penso _“E se eu usar SQLite no lugar do PhysicsFS?”_

##### DBA wanna be…

Embora o SQLite possua uma forma prática de ser fazer o que farei a seguir, o [SQLite Archive Files](https://www.sqlite.org/sqlar.html), irei apresentar o passo a passo.

Primeiro vamos criar uma tabela com dois campos, um deles para indentificação e o outro com o conteúdo binario em si.

> O SQLite (e a grande maioria dos bancos de dados) não suportam armazenar dados binários, para isso existe um tipo de dados especial chamado _BLOB (Binary Large OBject)_.

```bash
sqlite3 assets.db "CREATE TABLE IF NOT EXISTS assets (key TEXT PRIMARY KEY, blob BLOB);"
```

E é isso. O campo `key` é uma chave primaria e portanto tem um índice próprio, como sei?

```bash
$ sqlite3 assets.db
SQLite version 3.24.0 2018-06-04 14:10:15
Enter ".help" for usage hints.
sqlite> .schema assets
CREATE TABLE assets (filename TEXT PRIMARY KEY, blob BLOB);
sqlite> .indexes assets
sqlite_autoindex_assets_1
```

O próximo passo é inserir o arquivo da textura `texture001.tga` que será usada:

```bash
sqlite3 assets.db "INSERT INTO assets(key, blob) VALUES ('texture001', readfile('texture001.tga'));"
```

O SQLite tem uma função `readfile` que carrega o arquivo diretamente.

É possível verificar o tamanho do blob com a função `length`:

```bash
$ sqlite3 assets.db
SQLite version 3.24.0 2018-06-04 14:10:15
Enter ".help" for usage hints.
sqlite> select key, length(blob) from assets;
texture001|3686418
```

Que é exatamente o mesmo do arquivo original:

```bash
$ stat -f%z texture001.tga
3686418
```

Adaptando o exemplo acima para a API em C do SQLite temos:

```cpp
sqlite3 * db;
// abre o arquivo do banco de dados do sqlite.
sqlite3_open("assets.db", &db);
// ...

// preparamos a query.
const char * sql = "SELECT blob FROM assets WHERE key = ?";
sqlite3_stmt * stmt;
sqlite3_prepare_v2(db, sql, -1, &stmt, 0);

// "atrela" o valor `texture001` no primeiro parâmetro do sql, o `?`.
sqlite3_bind_text(stmt, 1, "texture001", -1, SQLITE_STATIC);

// executa a query "SELECT blob FROM assets WHERE key = 'texture001'".
sqlite3_step(stmt);

// criamos um `SDL_RWops` com os bytes do blob.
int bytes = sqlite3_column_bytes(stmt, 0);
const void * buffer = sqlite3_column_blob(stmt, 0);
SDL_RWops * rwops = SDL_RWFromMem(buffer, (sizeof(unsigned char) * bytes));

// finaliza.
sqlite3_reset(stmt);

// (como anteriormente) carrega a textura.
SDL_Surface * surface = IMG_Load_RW(rwops, 1);
SDL_Texture * texture = SDL_CreateTextureFromSurface(renderer, surface);
SDL_FreeSurface(surface);
```

## Benchmarks, é disso que o povo gosta!
Usando a função [SDL_GetPerformanceFrequency](https://wiki.libsdl.org/SDL_GetPerformanceFrequency) para mensurar o trecho responsável apenas por carregar a textura obtive os seguintes resultados:

```bash
$ file texture001.tga
texture001.tga: Targa image data - RGB 1280 x 960 x 24
$ ls -lh texture001.tga | awk '{print $5}'
3.5M
```

##### PhysicsFS (gzip compressed)
```bash
for i in {1..10}; do ./physfs; done
42.060247
40.972251
38.589466
40.684438
43.327696
38.578994
...
```

##### SQLite
```bash
for i in {1..10}; do ./sqlite; done
27.433850
30.553595
27.706754
27.282197
27.561867
27.853982
...
```

##### `IMG_Load("texture001.tga")` (A.K.A. diretamente)

```bash
for i in {1..10}; do ./a.out; done
22.792655
23.667172
22.286974
23.551452
22.094010
23.657177
...
```

> Acredito que se utilizado compressão no SQLite o uso de disco seria reduzido e como consequência resultados ainda melhores.

## Patches everywhere!
<p align="center">
  <img src="/public/2018-12-27-blobs-blurbs-bubbles/patches.jpg" alt="metalhead with lots of patches"/>
</p>

Uma das principais características do software é que ele não funciona e precisa constantemente ser remendado, e nos jogos não é diferente.

O MPQ tem um mecanismo de patches, como na época a maioria dos jogos eram distribuídas em mídias somente leitura, como o CD-ROM, era preciso uma outra abordagem, já que não era possível reescrever o `.mpq` original, portanto era criado uma espécie de corrente, então após o jogo carregar o jogo, as alterações eram aplicadas em cima, na mesma sequencia de que foram publicadas.

A ideia por trás de usar o SQLite no lugar do PhysicsFS é de aproveitar algumas características de um banco de dados, que é de… criar, atualizar, modificar e deletar de forma atômica!

> O arquivo de update do jogo poderia ser um conjunto de instruções SQL.  

Vamos desconsiderar o binário do jogo por hora, e vamos supor que uma nova textura foi adicionada no banco de dados do desenvolvedor, e por algum motivo desconhecido ele é preguiçoso e usou a ferramenta `sqldiff` para gerar o patch e não [schema migration](https://en.wikipedia.org/wiki/Schema_migration).

```
sqlite3 assets.db "INSERT INTO assets(key, blob) VALUES ('texture002', readfile('texture002.jpg'));"
```

> Estou usando texturas como exemplo pois geralmente é o tipo de arquivo que ocupa mais espaço em disco dos jogos. O exemplo vale para qualquer tipo de arquivo… seja textos, scripts, shaders, etc.  

```
$ sqldiff old.db assets.db > patch01.sql
$ # checando o conteúdo da atualização.
$ head -c 100 up.sql
INSERT INTO assets(rowid,"key", blob) VALUES(2,'texture002',x'ffd8ffe000104a46494600010100000100010%
$ ls -lh patch01.sql | awk '{print $5}'
663K
$ tar -cvzf patch01.tgz patch01.sql
$ ls -lh patch01.tgz | awk '{print $5}'
363K
```

> Como se trata de um arquivo `.jpeg` representado em hexadecimal dentro de um `.sql` os ganhos com compressão são pequenos.  

Agora basta a nossa ferramenta responsável por atualizar o jogo aplicar os patches na mesma sequencia que foram gerados.

Essa é uma forma bem simples e descomplicada de atualizar o jogo e é algo bem resolvido no mundo dos banco de dados há décadas.

É possível criar updates ainda menores, o Google Chrome tem um projeto chamado [courgette](http://dev.chromium.org/developers/design-documents/software-updates-courgette) que usa a ferramenta `bsdiff` combinada com um outro algoritmo descrito no link, podemos usar o [bsdiff](http://www.daemonology.net/bsdiff/) para gerar o patch do asset a ser atualizado e no cliente usar o `bspatch` para aplicar a modificação.

Além de todas essas vantagens, o uso do SQLite ainda possibilita o [data-driven programming](https://en.wikipedia.org/wiki/Data-driven_programming).

## Winterphobos

Pretendo utilizar o SQLite como descrito num novo projeto chamado [Winterphobos](https://github.com/skhaz/winterphobos), um motor de jogos minimalista, e uma das premissas é ser totalmente _"scriptável"_ em [lua](https://www.lua.org/) com [entity–component–system
](https://en.wikipedia.org/wiki/entity-component-system).

<p align="center">
  <img src="/public/2018-12-27-blobs-blurbs-bubbles/vaultboy.jpg" alt="metalhead with lots of patches"/>
</p>
