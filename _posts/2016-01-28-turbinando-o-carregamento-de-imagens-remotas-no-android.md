---
layout: post
title: Turbinando o carregamento de imagens remotas no Android
published: true
---

![image](/public/2016-01-28-turbinando-o-carregamento-de-imagens-remotas-no-android/android-fast.jpg)

Recentemente, precisei fazer um fine tuning de carregamento de imagens num app.

O cenário era o seguinte:
O app consiste em uma série de cardviews com imagens de background oriundos de diversos locais da internet, resultando em alguns problemas:

* Resolver DNS para cada domínio
* Handshake SSL para cada domínio
* Algumas imagens são infinitamente maiores do que o necessário
* Formatos diferentes (JPEG, PNG, GIF, WEBP, etc)
* Latência alta ou mesmo instabilidade
* O fato das imagens serem bem grandes, que imposibilita o OkHttp de fazer cache
* Alto uso de memória
* Não é legal fazer [Inline linking](https://en.wikipedia.org/wiki/Inline_linking)

Somando todos esses fatores, a experiência do usuário é prejudicada pela baixa performance.

Resolvi então usar o [thumbor](http://thumborize.me/) como proxy. O thumbor é um projeto open-source mantido pela Globo, que permite aplicar diversos efeitos, cortes, ajustes e filtros em imagens, tudo configurável pela URL.

> Exemplo
> [http://thumbor.thumborize.me/unsafe/300x100/filters:rotate(90)/placehold.it/250x150/ff0000](http://thumbor.thumborize.me/unsafe/300x100/filters:rotate(90)/placehold.it/250x150/ff0000)

Existe um recurso que usa [visão computacional](http://opencv.org/) para identificar rostos numa foto e no momento de recortar não cortar nenhum pescoço e/ou enquadrar todas as pessoas.

Com o thumbor eu posso redimensionar a imagem para o tamanho exato que cada dispositivo vai precisar, converter para outro formato menor, remover todas as informações ICC embutidas no arquivo, além de outros [filtros disponíveis](https://github.com/thumbor/thumbor/wiki/Filters).

Deploy do thumbor
=================
O deploy do thumbor é bem simples; existem imagens do Docker prontas para serem usadas, buildpacks do Heroku, Elastic Beanstalk ou mesmo manual.
Optei por usar o [OpsWorks](https://aws.amazon.com/opsworks/) com o [Chef](https://www.chef.io/chef/), na verdade já existia até um [cookbook](https://github.com/zanui/chef-thumbor) do thumbor pronto para ser usado.

Content Delivery Network (CDN)
==============================
Aproveitei e criei uma CDN usando o [CloudFront](https://aws.amazon.com/cloudfront/), assim as respostas do thumbor seriam cacheadas e distribuídas por todo os “_points of presence (PoPs)_”.

Pollexor
========
No Android temos uma biblioteca chamada [pollexor](https://github.com/square/pollexor), que permite escrever a URI do thumbor de uma maneira elegante usando [fluent interface](https://en.wikipedia.org/wiki/Fluent_interface).
Como já fazia uso do [picasso](http://square.github.io/picasso/) para o carregamento de imagens, usei o [picasso-pollexor](https://github.com/square/picasso/tree/master/picasso-pollexor), que funciona como um `RequestTransformer` para o Picasso, adicionando alguns parâmetros extras na URL de modo que a imagem seja recortada e enquadrada no tamanho exato do ImageView.

```java
Thumbor thumbor = Thumbor.create(BuildConfig.THUMBOR_URL, BuildConfig.THUMBOR_KEY);
final RequestTransformer transformer =
    new PollexorRequestTransformer(thumbor);

Picasso picasso = new Picasso.Builder(context)
    .requestTransformer(transformer)
    .downloader(new OkHttp3Downloader(httpClient))
    .build();
```

Desta forma, o uso do Picasso em conjunto com o thumbor fica totalmente transparente para o programador. Ao informar o tamanho da imagem e o tipo de crop, o `PollexorRequestTransformer` entra em ação alterando os parâmetros da URL, de forma totalmente transparente. Prático, não? :)

``` java
@Bind(R.id.background)
ImageView background;

...

picasso.load(url)
  .fit()
  .centerCrop()
  .into(background);
```

Com isso, resolvemos uma série de problemas:

* Será executado apenas um handshake de SSL
* Apenas um domínio a ser consultado no DNS
* A imagem é servida no tamanho exato que será exibida
* A latência é muito menor devido a CDN
* Possibilidade cachear em disco ou memória devido ao tamanho reduzido da imagem

Resultado
=========

| Normal | Otimizado |
| :---:|:---: |
| ![image](/public/2016-01-28-turbinando-o-carregamento-de-imagens-remotas-no-android/normal.gif) | ![image](/public/2016-01-28-turbinando-o-carregamento-de-imagens-remotas-no-android/optimized.gif) |

[Já acabou, Jéssica?](http://i.imgur.com/eJKIQEl.jpg)
=====================================================

O próximo passo é descobrir o sentido em que o usuário está rolando a lista e ir fazendo pre-fetch de algumas imagens, passando a impressão de carregamento instantâneo.
