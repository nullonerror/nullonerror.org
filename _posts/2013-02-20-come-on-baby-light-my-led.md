---
layout: post
title: >
  Come on baby, light my LED!
---

Esses dias alguém na lista [Garoa Hacker Space](https://groups.google.com/group/hackerspacesp) perguntou sobre como usar a [GPIO do RaspberryPi](http://elinux.org/RPi_Low-level_peripherals#General_Purpose_Input.2FOutput_.28GPIO.29) em conjunto com o framework [Django](https://www.djangoproject.com/) e as implicações em se rodar como root, pois como vocês bem sabem, só é possivel acessar a GPIO do RaspberryPi com permissão total, mas não é legal rodar o servidor também como root; logo, a solução que me veio à cabeça consistia em separar ambas as tarefas e usar um servidor de fila.

Pois bem, como eu estava sem o que fazer, decidi implementar. Segue abaixo um passo-a-passo de como fiz:

Antes de tudo, conecte-se via ssh no RaspberryPi e atualize o apt-get:

``` bash
sudo apt-get update
sudo apt-get upgrade
```

Se você ainda não instalou, instale o pacote build-essential. Nesse metapackage vem o compilador gcc, makefile, bibliotecas e outras coisas necessárias para o que vamos fazer a seguir.

``` bash
apt-get install build-essential
```

O servidor de fila escolhido para esta tarefa será o [ZeroMQ](http://www.zeromq.org/), e como se tratava de um teste rápido (e também porque já não tenho mais idade), optei por usar Python. Portanto, vamos instalar o binding do ZeroMQ para Python:

``` bash
sudo apt-get install python-zmq
```

Também vamos precisar do git:

``` bash
sudo apt-get install git-core
```

Vamos utilizar a biblioteca wiringPi para manipular a GPIO - aqueles que já escreveram código para o Arduino vão se sentir em casa, é bem simples de usar.
Como Python foi a linguagem escolhida, vamos fazer uso do binding da biblioteca wiringPi para python, e para isso, precisamos instalar o respectivo pacote de desenvolvimento:

``` bash
sudo apt-get install python-dev
```

Agora sim, estamos aptos para compilar o wiringPi-Python:

``` bash
git clone https://github.com/WiringPi/WiringPi-Python.git
cd WiringPi-Python
git submodule update --init
sudo python setup.py install
```

Orquestrando
============


A ideia é bem simples: vamos acender um LED RGB usando software PWM. Mas por que software? Porque o RaspberryPi tem apenas um PWM controlado por hardware, e vamos precisar de 3 portas (vermelho, verde e azul).


A interface será em html5, usando um colorpicker. Cada interação nesse componente envia para o servidor a nova cor através de uma requisição GET.


A tarefa do servidor é muito simples: chegou um novo valor, insere na fila do ZeroMQ e pronto

``` python
@route('/color/:param')
def color(param):
    socket.send(param)
```

Do outro lado (ou melhor, no processo vizinho), temos um processo rodando com privilégios de root, e que será o responsável por escrever na GPIO. Sua tarefa é igualmente simples e similar à anterior: fica esperando um novo valor chegar e escreve na GPIO, desta maneira:


``` python
while True:
  rgb = int(socket.recv())
  red = (rgb >> 16) & 0xFF
  green = (rgb >> 8) & 0xFF
  blue = rgb & 0xFF

  wiringpi.softPwmWrite(RED_PIN, red)
  wiringpi.softPwmWrite(GREEN_PIN, green)
  wiringpi.softPwmWrite(BLUE_PIN, blue)
```

É importante lembrar que o ZeroMQ está no modo publisher-subscriber.

… Tudo isso para acender um LED :grin:

Código fonte [https://github.com/skhaz/come-on-baby-light-my-LED](https://github.com/skhaz/come-on-baby-light-my-LED)

