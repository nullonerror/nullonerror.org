---
layout: post
title: >
  NULL on error underhood
---

... Ou como preparar o seu blog para escalar para milhões de visitas diárias, mas receber apenas algumas visitas... Da sua mãe, da sua tia, da sua avó, da prima e também da sua namorada :)

Inspirado no artigo [Do things, write about it](http://mdswanson.com/blog/2013/08/11/write-things-tell-people.html), resolvi escrever um pouco sobre como funciona o meu blog.

A princípio, optei por utilizar o [App Engine](http://developers.google.com/appengine/) por dois motivos: 1 - suporta python; e 2 - a quota gratuita é bem generosa para o  meu humilde blog :)

Meu objetivo era criar algo extremamente simples, similar a essas ferramentas que geram arquivos estáticos. Um projeto bem popular e que faz isso é o [Jekyll](http://jekyllrb.com/), mas como todo bom hacker, decidi reinventar a roda.
Já havia feito outros projetos que rodam sob o AppEngine, inclusive a primeira versão do blog, e todos esses projetos seguiam os _models_ da documentação, usando o webapp2 e a engine de renderização do django. Como o AppEngine possui um sistema de arquivos somente leitura, uma alternativa é salvar os dados no BigTable, o que não é um grande problema, uma vez que esses dados ficam no memcached na maior parte do tempo.

Porém, eu queria fazer algo diferente, queria estudar outros frameworks, e foi então que decidi usar o [bottle](http://bottlepy.org/) e o [jinja2](http://jinja.pocoo.org/) para renderização de templates. O resultado foi que aprendi **muito**, inclusive cheguei a escrever alguns filtros para o jinja2: um deles é o [imgur](https://github.com/skhaz/nullonerror/blob/experimental/imgur.py), responsável por subir imagens no imgur quando encontra a tag imgur e depois troca pela tag img do html; e o outro, ao encontrar a tag code, invocava o pygments, que por sua vez fazia parser do código e o coloria, mas acabei descartando este filtro e deixando essa tarefa com o cliente, usando o [prettify](http://code.google.com/p/google-code-prettify/).

![](http://i.imgur.com/oQdnf2x.png){: .center }

Como faço uso de uma quantidade considerável de javascript, pesquisei por algumas soluções de _lazy loading_, e a que mais me agradou foi o [RequireJS](http://www.requirejs.org/). Vamos ver como ficou essa carga logo abaixo:

``` javascript
var require = {
  baseUrl: "/static/js",

  shim: {
    'jquery': {
      exports: '$'
    },

    'bootstrap': {
      deps: ['jquery']
    },

    'prettify': {
      init: function () {
        prettyPrint()
      }
    },

    'jquery.raptorize': {
      deps: ['jquery']
    },

    'clippy': {
      deps: ['jquery'],
      init: function() {
        clippy.BASE_PATH = '/static/agents/'
        clippy.load('Clippy', function(agent) {
          agent.show()
          agent.speak('↑ ↑ ↓ ↓ ← → ← → B A')
          window.agent = agent
          window.setInterval(function() { agent.animate() }, 1500)
        });
      }
    },
  },

  deps: [
    'bootstrap',

    {% raw %}
    {% for module in modules %}
    '{{ module }}',
    {% endfor %}
    {% endraw %}
  ],

  callback: function() {
    $(function() {
      window._gaq = window._gaq || [];
      window._gaq.push(['_setAccount', '{ { blog.ga_tracking_code } }']);
      window._gaq.push(['_trackPageview']);

      $.ajax({
        type : "GET",
        url: 'http://www.google-analytics.com/ga.js',
        dataType : "script",
        data: null,
        cache : true,
        success: function() {
          // 0x90
        }
      })

      {% raw %}
      {% block ready %}
      {% endblock %}
      {% endraw %}
    })
  }
}
```

Adicionar o RequireJS ao projeto é muito simples. Primeiro você configura os módulos que vai usar - quando digo módulos, estou me referindo ao arquivo de javascript, que, no meu caso, se encontram no diretório _/static/js_, armazenado na váriavel baseUrl.

Outra configuração importante é o _shim_, este _array_ contém todos os módulos que eventualmente possam ser usados. Você pode indicar se algum módulo depende de outro, como no caso do _jQuery.raptorize_ que depende do _jQuery_; isso vai garantir que o _jQuery.raptorize_ será carregado depois que o _jQuery_ já tiver sido carregado! Nesta mesma seção, podemos inserir um código na váriavel _init_ que será executado logo após o módulo ser carregado. No caso do _[clippy](https://www.smore.com/clippy-js)_ temos o seguinte código:

``` javascript
init: function() {
  clippy.BASE_PATH = '/static/agents/'
  clippy.load('Clippy', function(agent) {
    agent.show()
    agent.speak(' ↑ ↑ ↓ ↓ ← → ← → B A')
    window.agent = agent
    window.setInterval(function() { agent.animate() }, 1500)
  });
```

Ainda neste pequeno bloco de código javascript, temos algumas linhas com _tags_ do jinja2, e um trecho de código que gostaria de destacar são as seguintes linhas:

``` javascript
deps: [
  'bootstrap',

  {% raw %}
  {% for module in modules %}
    '{{ module }}',
  {% endfor %}
  {% endraw %}
]
```

Como podemos ver, pretendo apenas carregar o módulo _bootstrap_, e como o mesmo depende do _jQuery_, teremos apenas esses dois módulos carregados por padrão; é aí que entra o jinja2 - esse trecho de código está no arquivo _layout.template_, que será herdado por todos os outros [arquivos de templates](https://github.com/skhaz/nullonerror/tree/experimental/templates). Por padrão, a variável _modules_ vem vazia, mas como podemos ver no template _[about](https://github.com/skhaz/nullonerror/blob/experimental/templates/about.template)_ a seguinte linha:

`{% raw %}{% set modules = ['jquery.raptorize', 'clippy'] %}{% endraw %}`

E é neste momento que atribuo a variável _modules_ com apenas o que vou usar, e não toda aquela tranqueira :)

Bom, isso é um pouco do que acontece no front-end, veremos agora o que se passa por trás das cortinas, no back-end.

Uma das coisas que ficou mais legal, modéstia à parte, foi a forma que o template correto é carregado e renderizado, sem ter que informar o nome do template para a função _render_, desta forma:

``` python
@route('/')
@memorize
def index():
  return render(entries=db.Query(Entry).order('-published').fetch(limit=25))

@route('/entry/:slug')
@memorize
def entry(slug):
  entry = db.Query(Entry).filter('slug =', slug).get()
  if not entry:
    from bottle import HTTPError
    raise HTTPError(404)
  else:
    return render(entry=entry)

@route('/about')
@memorize
def about():
  return render()
```

No trecho de código acima, temos 3 rotas, que são definidas pelo decorator _route_:

* **index**, que corresponde à url "/"
* **entry** que recebe o parâmetro "slug", que nada mais é do que uma [url amigavél](http://en.wikipedia.org/wiki/Clean_URL)
* **about**, que não recebe nenhum parâmetro

Nesse momento você deve estar se perguntando: mas como a função render sabe qual template carregar se essa informação não é passada?
De uma forma bem simples, meu caro leitor, lembra-se da [call stack](http://en.wikipedia.org/wiki/Call_stack)? Pois então, fazendo uso da biblioteca [inspect](http://docs.python.org/2/library/inspect.html) é possível examinar a call stack em tempo de execução, e assim, saber qual função chamou a função _render_. Com o nome da função, basta concatenar o nome dela com a extensão _template_ e renderizar com o jinja2 repassando os parâmetros passados

``` python
def render(*args, **kwargs):
  import inspect
  callframe = inspect.getouterframes(inspect.currentframe(), 2)
  template = jinja2.get_template('{}.template'.format(callframe[1][3]))
  return template.render(*args, **kwargs)
```

Isso é que é levar o conceito [Don't Repeat Yourself](http://en.wikipedia.org/wiki/Don) a sério.

Mais tarde, durante uma entrevista de emprego, vim a saber que alguns frameworks fazem algo parecido, pórem usando _exceptions_... Bom saber que ainda existem programadores criativos

E por falar em DRY, uma tarefa que acabou ficando extremamente repetitiva foi a manipulação de valores no memcache. Na [documentação do AppEngine](https://developers.google.com/appengine/docs/python/memcache/usingmemcache) temos o seguinte exemplo:

``` python
def get_data():
  data = memcache.get('key')
  if data is not None:
    return data
  else:
    data = self.query_for_data()
    memcache.add('key', data, 60)
    return data
```

Contudo, como só pretendo fazer _cache_ das chamadas _get_, decidi criar um decorator chamado _memorize_

``` python
from google.appengine.api import memcache

class memorize():
  def __init__(self, func):
    self.func = func

  def __call__(self, *args, **kwargs):
    key = '{}/{}'.format(self.func.__name__, '/'.join(kwargs.values()))
    result = memcache.get(key)
    if result is None:
      result = self.func(*args, **kwargs)
      memcache.add(key=key, value=result)
      return result
```

E adicionar em todas as rotas, como foi visto acima.

Basicamente o que esse decorator faz é gerar uma chave usando a url com seus parâmetros, assim, quando algum parâmetro é alterado, é forçada uma nova chamada à função, e logo após o retorno, é salvo no cache, usando a mesma chave gerada anteriormente. O uso do cache é importante para que o servidor não fique com _uma leseira danada_.

Para inserir uma nova entrada no blog, deve-se criar dois arquivos, cada um com uma extensão previamente estabelecida (poderia ser apenas um único arquivo e fazer um split usando uma determinada _tag_, mas achei que ficaria meio _chunchado_), então são dois arquivos com o mesmo nome, porém um deles é terminado em _.entry_, que contém o HTML que será exibido, e o outro, terminado em _.meta_ é um [YAML](http://www.yaml.org/) com as informações básicas, como título, data de publicação, tags e se é público ou não. Para automatizar essa inserção de dados, faço uso de [post-receive hooks](https://help.github.com/articles/post-receive-hooks) do github, ou seja, logo após um _git push_ o github faz uma chamada _POST_ com um _json_ descrito na documentção do github; com esse json em mãos, basta fazer o _parsing_ e ver quais arquivos foram modificados ou adicionados, com as extensões mencionadas acima:

``` python
for commit in payload['commits']:
  for action, files  in commit.iteritems():
    if action in ['added', 'modified']:
    for filename in files:
      basename, extension = os.path.splitext(filename)
      if extension in ['.entry', '.meta']:
```

Assim, basta montar a url completa com a função build_url:

``` python
github = {
  'url' : 'https://raw.github.com',
  'repository' : 'nullonerror-posts',
  'user' : 'skhaz',
  'branch' : 'master',
}

def build_url(filename):
  return "%s/%s" % ('/'.join([v for k, v in github.iteritems()]), filename)
```

Note o "raw" na url, esse é o caminho para o arquivo crú, isso significa que posso baixar o arquivo no seu formato original, assim como foi mencionado acima, tenho dois tipos de arquivos que são tratados de forma especial, como visto abaixo:

``` python
from google.appengine.api import urlfetch
from utils import build_url
result = urlfetch.fetch(url = build_url(filename))
if result.status_code == 200:
  entry = Entry.get_or_insert(basename)
if extension.endswith('.entry'):
  entry.content = jinja2.from_string(result.content.decode('utf-8')).render()
else:
  try:
    import yaml
    meta = yaml.load(result.content)
  except:
    logging.error('Failed to parse YAML')
  else:
    entry.title = meta['title']
    entry.categories = meta['categories']
    entry.published = meta['published']
    entry.slug = basename
    entry.put()
```

Assim como eu posso inserir ou atualizar as entradas, posso fazer o mesmo na hora de remover

``` python
elif action in ['removed']:
  for filename in files:
    basename, extension = os.path.splitext(filename)
    entry = Entry.get_by_key_name(basename)
    if entry: entry.delete()
```

No final do processo, faço um _flush_ no memcached.

Outra coisa bacana no AppEngine, e que não é exclusividade do mesmo, é o [PageSpeed](https://developers.google.com/speed/pagespeed/). Esse módulo comprime todos os assets, _recomprime_ todas as imagens para formato webp e as serve caso o navegador suporte, codifica em base64 e inclui no html assets muito pequenos para evitar requisições, unifica javascript e css, entre outras técnicas descritas no manual.

Além disso, uso o [CloudFlare](https://www.cloudflare.com/) para [CDN](http://en.wikipedia.org/wiki/Content_delivery_network), que me ajuda a salvar um bocado de banda :)

Ainda falta implementar muita coisa, estive pensando em escrever um editor em Qt e usar a [libgit2](http://libgit2.github.com/) para commitar e fazer push diretamente das alterações.

Enfim... É isso, obrigado por ter lido esse texto longo e chato :)
