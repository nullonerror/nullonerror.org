---
layout: post
title: >
  TornadIO2 & socket.io: A dupla dinâmica
---

Já tem um bom tempo que eu estava querendo fazer algo usando [WebSockets](http://www.websocket.org/) junto ao servidor assíncrono [Tornado](http://www.tornadoweb.org/). Pesquisando meio que em paralelo e seguindo alguns links, encontrei o [SockeIO](http://socket.io/), um projeto bem interessante que fornece uma camada de abstração do WebSockets, já que o mesmo é bem parecido com um [socket](http://en.wikipedia.org/wiki/Network_socket), e ainda fornece dois fallbacks caso o navegador não suporte websockets - um deles é fazendo long polling e o outro usando o plugin flash.  

Outro projeto que encontrei foi o [TornadIO2](https://github.com/MrJoes/tornadio2). Ele implementa todo o protocolo do [SockeIO](http://socket.io/), e como o próprio nome sugere, usa o  [Tornado](http://www.tornadoweb.org/), o qual já conheço há algum tempo :)

**Colocando a dupla dinâmica para funcionar**

``` bash
git clone git://github.com/mrjoes/tornadio2.git
cd tornadio2
pip install -r requirements.txt
python setup.py install
```

Minha intenção não era escrever um [hello world](https://en.wikipedia.org/wiki/Hello_world_program) sobre o assunto, e sim dizer que atualizei o projeto [Come on baby, light my LED!](http://nullonerror.org/2013/02/20/come-on-baby-light-my-led/), e sinceramente? Não sei porque não usei websockets desde o início...

[Código fonte](https://github.com/skhaz/come-on-baby-light-my-LED)
