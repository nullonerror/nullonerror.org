---
layout: post
title: >
  Criando um bot de notícias para o Telegram usando Scrapy e Firebase
---

### Problema

Eu costumo pegar com frequência a rodovia [Régis Bittencourt](http://www.autopistaregis.com.br/) e o que acontece com frequência é o trânsito parar completamente no meio do nada e sem acesso à internet, então eu fico sem a mínima noção do que está acontecendo e em quanto tempo conseguirei chegar ao meu destino.

Pensando nisso, decidi escrever um pequeno `bot` para o Telegram que publica num canal as notícias da estrada! Como de costume no NULL on error, vou explicar como fiz.

### Web scraping

![Squitter](/public/2017-07-10-criando-um-bot-de-noticias-para-o-telegram-usando-scrapy-e-firebase/squitter.jpg)

O primeiro passo é extrair as informações do site. Eu optei por utilizar o framework [Scrapy](https://scrapy.org/), por alguns motivos que ficarão bem claros abaixo e por ter bastante experiência escrevendo web crawlers com o Scrapy - eu não pretendo escrever um tutorial a respeito neste artigo, isso ficará para uma próxima oportunidade.

Antes de tudo, eu preciso definir o que eu quero extrair; isso é feito definindo uma classe com _N_ [propriedades](https://doc.scrapy.org/en/latest/topics/items.html#scrapy.item.Field) herdando de [scrapy.Item](https://doc.scrapy.org/en/latest/topics/items.html)

```python
class Entry(Item):
    uid = Field()
    spider = Field()
    timestamp = Field()
    content = Field()
```

Como é possível notar, a aranha, ou _crawler_, ficou bem simples, mas vou explicar cada parte a seguir.

```python
class RegisSpider(CrawlSpider):
    name = 'regis'
    allowed_domains = ['autopistaregis.com.br']
    start_urls = ['http://www.autopistaregis.com.br/?link=noticias.todas']
    rules = (
        Rule(LinkExtractor(allow=r'\?link=noticias.?ver*'), callback='parse_news'),
    )

    def parse_news(self, response):
        loader = EntryLoader(item=Entry(), response=response)
        loader.add_xpath('content', '//*[@id="noticia"]/p[not(position() > last() -3)]//text()')
        return loader.load_item()
```

A propriedade `start_urls ` indica onde a aranha vai iniciar a varredura de páginas

Após isso, definimos algumas regras. Vou usar um [LinkExtractor](https://doc.scrapy.org/en/latest/topics/link-extractors.html), que, como o próprio nome diz é um componente para extrair links seguindo uma regra das páginas encontradas. Nesse caso eu usei uma expressão regular que bate com todas as URLS de notícias do site, e defino um callback que será chamado para cada página, chamado `parse_news`.

```python
LinkExtractor(allow=r'\?link=noticias.?ver*'), callback='parse_news')
```

Então é aqui que a mágica toda acontece: passei algum tempo analisando o código fonte da página e usando o inspetor web para poder gerar um xpath que bata com notícia, excluindo as informações extras na página.

### XPath

O [XPath](https://www.w3schools.com/xml/xml_xpath.asp) é uma forma de atravessar o HTML e extrair alguma informação específica. É uma linguagem bem poderosa. Nesse caso eu usei a expressão `[not(position() > last() -3)]` para excluir os últimos 3 parágrafos marcados pela tag `<p>`, que o site sempre coloca como uma forma de rodapé. Infelizmente, nem sempre os sites seguem boas práticas, o que me facilitaria e muito a extração dos dados!

```python
loader.add_xpath('content', '//*[@id="noticia"]/p[not(position() > last() -3)]//text()')
```

Os outros campos, como ID da noticía e timestamp são "extraídos" usando um _middleware_ chamado [scrapy-magicfields](https://github.com/scrapy-plugins/scrapy-magicfields), desta maneira:

```python
MAGIC_FIELDS = {
    'uid': "$response:url,r'id=(\d+)'",
    'spider': '$spider:name',
    'timestamp': "$time",
}
```

O próximo passo é rodar o web crawler periodicamente. Eu usei o sistema de cloud do [Scrapinghub](https://scrapinghub.com/), que é a empresa que desenvolve o Scrapy e outras ferramentas de scraping; nele, eu posso configurar para rodar de tempos em tempos o crawler. No meu caso, eu configurei para rodar a cada 30 minutos,

Mesmo que possível, eu não posso publicar diretamente, apenas as novas notícias, caso contrário, toda vez que o crawler rodar eu estaria poluindo o canal com as notícias repetidas. Então eu decidi salvar num banco de dados intermediário para conseguir distinguir o que é novo do que já foi indexado.

### Persistência

Eis que entra o [Firebase](https://firebase.google.com/), e sua nova funcionalidade chamada de [functions](https://firebase.google.com/docs/functions), com o qual, eu posso escrever uma função que reage a determinados eventos no banco de dados - por exemplo, quando um novo dado é inserido.


```javascript
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const request = require('request-promise');
const buildUrl = require('build-url');

admin.initializeApp(functions.config().firebase);


exports.notifyChannel = functions.database.ref('/news/{what}/{uid}')
  .onCreate(event => {
    const config = functions.config().telegram;
    const url = buildUrl('https://api.telegram.org', {
      path: `bot${config.bot.token}/sendMessage`,
      queryParams: {
        chat_id: config.channel.chat_id,
      }
    });

    return request({
      method: 'POST',
      uri: url,
      resolveWithFullResponse: true,
      body: {
        text: event.data.val().content
      },
      json: true
    }).then(response => {
      if (response.statusCode === 200) {
        return response.body.id;
      }
      throw response.body;
    }
  );
});
```

Essa função é bem simples; basicamente, em qualquer evento de _onCreate_ ela é chamada, então faço uma chamada `POST` na API do Telegram com o nome do canal, token do bot e conteúdo, que, no caso, é o texto da notícia.

![Pregunta](/public/2017-07-10-criando-um-bot-de-noticias-para-o-telegram-usando-scrapy-e-firebase/pregunta.jpg)

### E como os itens são salvos no Firebase?

Resposta: Recentemente, o Firebase lançou uma API para acessar a SDK usando Python, então eu escrevi um [_item pipeline_](https://doc.scrapy.org/en/latest/topics/item-pipeline.html) chamado [scrapy-firebase](https://github.com/skhaz/scrapy-firebase) que usa essa API para escrever no banco de dados do Firebase, a cada item coletado do Scrapy, o método [process_item](https://github.com/skhaz/scrapy-firebase/blob/master/scrapy_firebase.py#L35) do pipeline é chamado, e nesse método é salvo o item no Firebase.

```python
class FirebasePipeline(BaseItemExporter):

    def load_spider(self, spider):
        self.crawler = spider.crawler
        self.settings = spider.settings

    def open_spider(self, spider):
        self.load_spider(spider)

        configuration = {
            'credential': credentials.Certificate(filename),
            'options': {'databaseURL': self.settings['FIREBASE_DATABASE']}
        }

        firebase_admin.initialize_app(**configuration)
        self.ref = db.reference(self.settings['FIREBASE_REF'])

    def process_item(self, item, spider):
        item = dict(self._get_serialized_fields(item))

        child = self.ref.child('/'.join([item[key] for key in self.keys]))
        child.set(item)
        return item
```

### Próximos passos

Ao mesmo tempo em que eu notifico o [canal](https://t.me/RegisBittencourt) do Telegram, estou usando o [Cloud Natural Language API](https://cloud.google.com/natural-language/) para classificar a notícia, e, em seguida, salvo no [BigQuery](https://bigquery.cloud.google.com/). Após algum tempo, acredito que será possível usar o `BigQuery` para determinar quais trechos, quando e o quê costuma dar mais problemas à rodovia, através de [_data mining_](https://en.wikipedia.org/wiki/Data_mining)!
