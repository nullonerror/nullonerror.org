---
layout: post
title: >
  Empreendendo sem dinheiro
---

Criei uma espécie de _desafio mental_, esse desafio consiste em resolver problemas já enfrentados ou de outras origens de forma criativa, em pouco tempo e se possível evolvendo pouco ou nenhum custo!

E o desafio da semana foi criar um daqueles projetos de [“media indoor”](https://www.google.com/search?q=mídia+indoor&tbm=isch).

Então pensei: “já sei vou usar [grpc](https://grpc.io/), [s3 rsync](https://rclone.org/), [elastic transcoder](https://aws.amazon.com/elastictranscoder/), [fastly](https://www.fastly.com/), frontend do admin em [react](https://reactjs.org) e é claro [kubernetes](https://kubernetes.io/)!”

Já no cliente, que é responsável por tocar os vídeos...: “vou escrever em [Qt](https://www.qt.io), criar a interface em [QML](https://en.wikipedia.org/wiki/QML), usar [boost.asio](https://www.boost.org/doc/libs/1_69_0/doc/html/boost_asio.html) para o meu downloader e criar uma distribuição de Linux embarcado usando o [yocto](https://www.yoctoproject.org) !“.

**Nope...**

### Painel administrativo

As pessoas,  e desse ramo principalmente, estão acostumadas a usar planilhas para as mais variadas tarefas, então por que não usar uma planilha como _“admin”_?

![Google Sheets](/public/2019-01-10-empreendendo-sem-dinheiro/gsheets.jpg){: .center }

### Envio, armazenamento, transcodificação e distribuição de vídeos

Ao invés de desenvolver um complexo sistema de gerenciamento de arquivos de vídeo, com transcodificação usando as ferramentas que citei acima, usando [lambda](https://aws.amazon.com/lambda/) e outras coisas, vamos usar o YouTube.

Quê?

É isso mesmo, no nosso protótipo vamos usar o YouTube, pois não tem nenhum custo e já faz a conversão e distribuição do vídeo nos mais variados formatos e tamanhos.

> Atenção: De acordo com [os termos de uso](https://www.youtube.com/static?template=terms) do YouTube não é permitido reproduzir o conteúdo da plataforma fora do player do youtube, o que estou demonstrando é apenas para fins educacionais.  

### [O nosso work é playá](https://www.youtube.com/watch?v=EJruqzsvza4)

Nada mais do que um pequeno _script_ em bash será necessário para executar as tarefas de baixar a _playlist_, os vídeos, a remoção de vídeos não mais usados entre outras coisas.

Já o _player_ propriamente dito é o [omxplayer](https://elinux.org/Omxplayer), que é capaz de decodificar vídeos usando aceleração por hardware; `omxplayer` foi escrito especialmente para a _GPU_ do [Raspberry Pi](https://www.raspberrypi.org/) e faz uso da API [OpenMAX](https://www.khronos.org/openmax/), é extremamente eficiente.

O trecho abaixo é de um [apps script](https://developers.google.com/apps-script/) que transforma a primeira coluna da planilha num array de objetos e serializa a reposta num _JSON_.

```js
function doGet(request) {
  var app = SpreadsheetApp;
  var worksheet = app.getActiveSpreadsheet();
  var sheet = worksheet.getSheetByName(request.parameters.sheet);
  if (sheet) {
    var range = sheet.getDataRange();
    var values = range.getValues();
    var headers = values.shift();
    var playlist = values.map(function (el) { return { url: el[0] }; });
    return ContentService.createTextOutput(JSON.stringify({ playlist: playlist }))
      .setMimeType(ContentService.MimeType.JSON);
  }
}
```

É possível publicar o script acima num [endereço público e de acesso anônimo](https://developers.google.com/apps-script/guides/web#deploying_a_script_as_a_web_app), de modo que seja possível baixar o _JSON_ até mesmo pelo _cURL_, e é com essa reposta que iremos usar para saber quais arquivos baixar e gerar a _playlist_:

```bash
$ curl -sL "https://script.google.com/macros/s/${...}/exec?sheet=Sheet1" | jq
{
  "result": [
    {
      "url": "https://www.youtube.com/watch?v=..."
    },
    ...
  ]
}
```

Com uma simples entrada no `cron`  é possível criar um agendamento para baixar a playlist de tempos em tempos:

```shell
*/30 * * * * user curl -sL "https://script.google.com/macros/s/${...}/exec?sheet=Sheet1" > playlists/1.json
```

A função `download` usa a ferramenta [jq](https://stedolan.github.io/jq/) para gerar uma lista de _urls_ a serem baixadas pelo [youtube-dl](https://rg3.github.io/youtube-dl/) que por sua vez executa um pequeno _script_ (`--exec`) para adicionar o arquivo recém baixado para a playlist, tomando cuidado para não duplicar:

```shell
download() {
  cat playlists/*.json | jq '.[].url' \
    | xargs youtube-dl --exec "grep -sqxF '{}' $playlist || echo '{}' >> $playlist"
}
```

> Alguns parâmetros do `youtube-dl` foram omitidos pois foram movidos para o arquivo de configuração global.  

Com o [entr](http://entrproject.org/) é possível monitorar se algum arquivo foi modificado ou mesmo adicionado novos arquivos no diretório; se isso acontecer, a função `download` será chamada:

```shell
watch() {
  while :; do
    ls -d playlists/*.json | entr -d "$0" download
  done
}
```

De tempos em tempos é necessário remover os arquivos antigos e downloads incompletos; a função `recycle` remove todos os arquivos do tipo vídeo modificados pela última vez há mais de 7 dias e que não estão sendo usados:

> A razão de ser alguns dias depois e não imediatamente é ser maleável caso tenha sido algum equívoco.

```shell
recycle() {
  declare -a args=(
    -mtime +7
    -type f
  )

  while read -r uri; do
    args+=(-not -name "$uri")
  done <<< "$(cat $playlist)"

  find "$PWD" "${args[@]}" -exec bash -c "file -b --mime-type {} | grep -q ^video/" \; -delete
}
```

> Todas essas funções podem ser chamadas inúmeras vezes sem efeitos indesejados.

Tocar a playlist é a parte mais fácil:

```shell
play() {
  setterm -cursor off

  export DISPLAY=":0.0"

  while :; do
    while read -r uri; do
      omxplayer --refresh --no-osd --no-keys "$uri"
      xrefresh -display :0
    done <<< "$(cat $playlist)"
  done
}
```

> Graças ao `omxplayer` o consumo de CPU fica bem baixo, mesmo em 1080@60fps, algo em torno de ~0.5% num Raspberry 3.

O próximo passo é contabilizar algumas estatísticas, como o número de vezes que um vídeo foi tocado, se teve alguma interrupção por falta de energia ou por problemas técnicos, etc.

Para isso uma boa pedida é o [papertrail](https://papertrailapp.com/), com essa ferramenta é possível centralizar todos os logs da máquina, exportar para o [BigQuery](https://cloud.google.com/bigquery) e executar as consultas na mesma planilha que ficam os vídeos.

Ops… Acho que minha febre por _cloud computing_ voltou :-)
