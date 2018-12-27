---
layout: post
title: >
  Escondendo informações dentro de imagens
---

Quando criança, existia uma brincadeira chamada [mensagem secreta](http://educador.brasilescola.com/estrategias-ensino/mensagem-secreta.htm) que consiste em escrever algo em uma folha de sulfite com suco de limão e entregar essa folha para algum colega que sabia que ao passar uma vela uma mensagem seria relavada, sem que qualquer um dos intermediários soubessem.

Podemos dizer que essa brincadeira era uma forma de **esteganografia**

> "Esteganografia (do grego "escrita escondida") é o estudo e uso das técnicas para ocultar a existência de uma mensagem dentro de outra, uma forma de segurança por obscurantismo. Em outras palavras, esteganografia é o ramo particular da criptologia que consiste em fazer com que uma forma escrita seja camuflada em outra a fim de mascarar o seu verdadeiro sentido." - [Wikipédia](http://pt.wikipedia.org/wiki/Esteganografia)

Hoje vou apresentar um outro tipo de esteganografia, a que usa imagens para ocultar textos nos píxels!

Uma imagem é composta por pixels, e cada píxel representa o menor ponto de cor possível usando um numero N de bits, quanto mais bits por cor, mais cores o píxel pode representar.

No meu exemplo vou focar apenas em imagem de _32 bits_ (_RGBA_ ou _ARGB_) onde são usados _8 bits_ por componente de cor. Obviamente a técnica é facilmente adaptável para outros formatos.

![image](/public/2015-04-05-escondendo-informacoes-dentro-de-imagens/rgba.png "https://commons.wikimedia.org/wiki/File:HexRGBAbits.png")

O que acontece se eu alterar um único bit do componente vermelho de todos os pixels? Mesmo com a imagem original ao lado, seriamos incapazes de perceber a diferença, somente com algum algoritmo de _hashing_ como o SHA1 seria possível ver que os arquivos são diferentes.

Logo, posso usar deste mesmo truque de alterar píxels para esconder uma mensagem dentro da imagem, e apenas quem conhecer a implementação saberá como extrair a mensagem.

Mas para isso é preciso separar cada bit da minha mensagem e alterar apenas um ou dois bits de cada componente de cor, parece pouco espaço, mas se fizermos as contas, uma imagem de 800x600 que é considerada hoje de baixa resolução pode comportar

> 800 width * 600 height = 480000 píxeis  
> 480000 píxels * 4 component = 1920000 bits  
> 1920000 bits / 8 = 240000 bytes  

Ou seja, podemos ter uma mensagem de até ~30KB numa imagem de 800x600 :)

Lembre-se, estamos falando em pixels e não em tamanho de arquivo, isso fica por conta do formato escolhido. E por falar em formato, só funciona com formatos [lossless](http://en.wikipedia.org/wiki/Lossless_compression#Graphics)

## Implementação

Para alcançamos o nosso objetivo é preciso dominar a **arte milenar de escovar bits**. Existe um excelente texto sobre o assunto chamado: [Bit Twiddling Hacks](https://graphics.stanford.edu/~seander/bithacks.html)

Escrevendo uma mensagem oculta:

```cpp
bool write(const QString& in, const QString& out, const QString& text){
  QImage image;
  if (!image.load(in))
      return false;

  QImage result = image.copy();
  int size = text.size();

  QByteArray bytes;
  bytes.reserve(size + headerSize);
  bytes += QString("%1").arg(size, headerSize, 10, QChar('0'));
  bytes += text.toLocal8Bit();

  QBitArray bits = byteArrayToBitarray(bytes);

  // Percorre cada pixel da imagem
  for (int index = 0, y = 0; y < image.height(); ++y) {
    for (int x = 0; x < image.width(); ++x) {
      if (index >= bits.count())
        break;

      // Extrai cada um dos seus componentes individualmente
      QRgb pixel = image.pixel(x, y);
      int red   = qRed(pixel);
      int green = qGreen(pixel);
      int blue  = qBlue(pixel);
      int alpha = qAlpha(pixel);

      // Para cada componente, pegamos um bit da mensagem
      // e ligamos ou desligamos o último bit do componente
      // para ligar: componente | (1 << 0x00)
      // para desligar: componente & ~(1 << 0x00)
      red   = bits[index + 0] ? red   | (1 << 0x00) : red   & ~(1 << 0x00);
      green = bits[index + 1] ? green | (1 << 0x00) : green & ~(1 << 0x00);
      blue  = bits[index + 2] ? blue  | (1 << 0x00) : blue  & ~(1 << 0x00);
      alpha = bits[index + 3] ? alpha | (1 << 0x00) : alpha & ~(1 << 0x00);

      // A mesma coisa para o penúltimo bit
      red   = bits[index + 4] ? red   | (1 << 0x01) : red   & ~(1 << 0x01);
      green = bits[index + 5] ? green | (1 << 0x01) : green & ~(1 << 0x01);
      blue  = bits[index + 6] ? blue  | (1 << 0x01) : blue  & ~(1 << 0x01);
      alpha = bits[index + 7] ? alpha | (1 << 0x01) : alpha & ~(1 << 0x01);

      // Escreve novamente o pixel no seu local de origem
      result.setPixel(x, y, qRgba(red, green, blue, alpha));

      index += 8;
    }
  }

  return result.save(out);
}
```

Lendo uma mensagem oculta em uma imagem:

```cpp
QByteArray read(const QString& filename) {
  QBitArray bits(8);
  QByteArray bytes;
  bytes.reserve(headerSize);
  int bytesToRead = 0;

  QImage image;
  if (image.load(filename)) {
    // Percorre cada píxel da imagem
    for (int y = 0; y < image.height(); ++y) {
      for (int x = 0; x < image.width(); ++x) {
        uint32_t index = 0;
        QRgb pixel = image.pixel(x, y);

        // Para cada pixel, extraio o último e o penúltimo bit
        // de cada componente de cor
        bits[index++] = qRed(pixel)   & 1 << 0x00;
        bits[index++] = qGreen(pixel) & 1 << 0x00;
        bits[index++] = qBlue(pixel)  & 1 << 0x00;
        bits[index++] = qAlpha(pixel) & 1 << 0x00;

        bits[index++] = qRed(pixel)   & 1 << 0x01;
        bits[index++] = qGreen(pixel) & 1 << 0x01;
        bits[index++] = qBlue(pixel)  & 1 << 0x01;
        bits[index++] = qAlpha(pixel) & 1 << 0x01;

        // Converte os 8 bits para 1 byte e insiro na lista bytes
        bytes += bitArrayToByteArray(bits);

        // É preciso saber quantos bytes devemos ler
        // para isso um cabeçalho com essa informação
        // é inserido logo no inicio do processo de escrita
        if (!bytesToRead && bytes.size() == headerSize) {
          bool ok;
          bytesToRead = bytes.toInt(&ok);
          if (!ok)
            return bytes;

          bytes.clear();
          bytes.reserve(bytesToRead);
        }

        // Leu tudo que tinha para ler, retorna os bytes
        if (bytes.size() == bytesToRead) {
          return bytes;
        }
      }
    }
  }

  return bytes;
}
```

## Proof

```
$ file gioconda.png
gioconda.png: PNG image data, 404 x 410, 8-bit/color RGBA, non-interlaced
$ ./stenog -i gioconda.png -o gioconda_stenog.png -m "flipping bits whilst updating pixels"
$ file gioconda_stenog.png
gioconda_stenog.png: PNG image data, 404 x 410, 8-bit/color RGBA, non-interlaced
$ ls -lah *.png
-rw-r--r--@ 1 Skhaz  staff   378K Apr  3 17:33 gioconda.png
-rw-r--r--  1 Skhaz  staff   394K Apr  3 17:46 gioconda_stenog.png
$ ./stenog -i gioconda_stenog.png
flipping bits whilst updating pixels
```

O tamanho do arquivo mudou ligeiramente de tamanho devido ao formato utilizado, no caso PNG.

_Essa técnica pode ser usada para ocultar não somente textos, mas como outras imagens, sons, ou qualquer tipo de dado._

## Talk is cheap. Show me the code

O código fonte se encontra neste [gist](https://gist.github.com/skhaz/4e83e245f41560634be4)

![decifra-me ou devoro-te](/public/2015-04-05-escondendo-informacoes-dentro-de-imagens/gioconda_stenog.png){: .center }
