---
layout: post
title: >
  Luz, câmera, ação!
---

Esse artigo vai trazer uma compilação dos meus estudos sobre multimídia no Qt usando a poderosa libVLC, mas antes de tudo, alguns já devem estar se
perguntando "Porque usar o VLC sendo que o Qt já vem com o Phonon embarcado?", Essa é uma boa pergunta, o framework Phonon do projeto KDE é excelente
e cumpre muito bem seu papel, para cada plataforma é usado um backend de vídeo e áudio, no Windows é o DirectShow, no OSX o QuickTime, no Linux e "unixes" em geral, pode ser o GStreamer, Xine ou mesmo o VLC, dentro outros, a lista completa de backends suportados é [essa](https://projects.kde.org/projects/kdesupport/phonon).

A razão pela qual eu escolhi o VLC como backend de multimídia e descartei a hipótese de usar o Phonon (por enquanto), é que eu queria reproduzir vídeo dentro do Graphics View Framework, e devido a forma que é implementado o desenho no Phonon isso não foi possível, apesar que.. há algum tempo, no Qt labs foi [postado](http://labs.qt.nokia.com/2008/11/28/videos-get-pimped/) uma melhoria bem significativa na dupla Qt e Phonon, onde é possível reproduzir vídeos com aceleração de hardware, incluindo zoom, alpha e transformação, a primeira coisa que fiz (na verdade a segunda, após ler o artigo dos trolls[1]) foi testar essa maravilha, e funcionou, mas após algum tempo, a aplicação parava de responder e fechava, pelo visto era um experimento windows-only :(

Voltando ao VLC, eu o uso desde muito tempo, e sempre achei ele fantástico, toca praticamente qualquer tipo de mídia, graças a implementação de codecs proprietários de forma colaborativa, e recentemente com o anuncio de que a libVLC será LGPL me deixou bem animado para fazer alguns experimentos :)

Minha primeira tentativa com a libVLC foi a mais simples possível, fiz um clone do repositório, compilei, crie uma classe que herda QWidget, instanciei a libVLC, passei o "winId" do widget para o VLC, não vou dizer que funcionou de primeira porque eu esqueci de informar onde estava os plugins, e também não funcionou de segunda porque o diretório que informei, algo como _"lib/vlc/plugins"_ aparentemente era inválido, fui até o diretório de saída do executável, e notei que ele havia criado um link simbólico de nome "plugins" para "modules", bastou informar o caminho correto e pronto, funcionou perfeitamente. Agora vem a segunda parte, eu sabia que era possível usar qualquer _widget_ dentro do Graphics View Framework usando o componente QGraphicsProxyWidget, maravilha, vamos tentar então, o código ficou mais ou menos assim:

```cpp
MyVideoPlayer video;
QGraphicsProxyWidget *proxy = scene.addWidget(&video);
```

É... não funcionou, apenas para tirar teima, testei com um outro Widget qualquer, no caso, foi o QPushButton, e funcionou perfeitamente... Me debrucei na documentação do QGraphicsProxyWidget para tentar entender porque não havia funcionado com o meu widget, até que encontrei o seguinte trecho:

> Note that widgets with the Qt::WA_PaintOnScreen widget attribute set and widgets that wrap an external application or controller cannot be embedded. Examples are QGLWidget and QAxWidget.

Outra decepção... resumidamente, como meu widget passava o ID da janela (no caso do widget mesmo) para a libVLC, ele estava
 sendo pintando por uma outra aplicação, logo, nunca funcionaria.

Minha segunda tentativa, diria que foi um pouco mais hardcore, olhando na wiki do VLC, encontrei um exemplo de como usar com o SDL, como eu já conheço bem essa biblioteca, resolvi baixar o exemplo, mas antes disso dei uma boa lida no código fonte, porque eu sabia que era possível passar o ID da janela do SDL, minha analise foi bem otimista, além das operações de blit, foi usado callbacks "libvlc_video_set_callbacks" para que o VLC pudesse escrever em uma área da memória, previamente alocado por SDL_CreateRGBSurface, beleza, vamos testar então. A performance não foi tao boa quanto usando a solução anterior, mas mesmo assim era muito boa.

Vamos portar esse código para Qt então, ao invés de criar uma classe que herdava QWidget, parti logo para a classe base QGraphicsObject, a principal diferença, entre a versão com SDL e essa, é que na função de unlock, eu emitia um sinal, que havia sido previamente conectado a um slot, basicamente o que ele fazia era instanciar a classe QImage e passar o ponteiro dos pixels que o VLC renderizou, e chamar o método update, para forçar uma chamada ao método _paint_ o mais breve possível, e no final, destrancar a mutex.

```cpp
QImage image = QImage(callback->pixels, bounds.width(), bounds.height(), QImage::Format_RGB32);
callback->mutex->unlock();
update();
```

Já no método paint, basta apenas desenhar a imagem:

```cpp
painter->drawImage(QPoint(0, 0), image);
```

Resumindo... Apesar do pequeno overhead[2], a versão em Qt ficou bem mais performática do que a em SDL, e funcionou exatamente como eu queria, que era poder reproduzir um vídeo dentro de um QGraphicsView e desenhar widgets sobre o vídeo tocando, além é claro de poder aplicar transparência, rotacionar/redimensionar, e todas as outras coisas possíveis no Graphics View Framework, e de bônus, posso usar com QML/QtQuick :D

Bom, é isso aí, o código fonte está em [github.com/skhaz/qt-youtube](https://github.com/skhaz/qt-youtube). Em breve, minha próxima tentativa será usando pixel buffer (QGLBuffer).

O resultado pode ser visto no vídeo a seguir:

<iframe width="420" height="315" src="https://www.youtube.com/embed/pYhqVsZ6fN8" frameborder="0" allowfullscreen></iframe>

1 - Trolls eu me refiro aos funcionários da ex-trolltech, e não ao meme.

2 - Na minha maquina atual, com um processador Core 2 Duo 2.26GHz, roda um vídeo FullHD consumindo cerca de 40% do processador, usando o VLC, o consumo fica em torno de 16%.

Referências:

* [LibVLC_SampleCode_SDL](http://wiki.videolan.org/LibVLC_SampleCode_SDL)
* [Videos Get Pimped](http://labs.qt.nokia.com/2008/11/28/videos-get-pimped/)
