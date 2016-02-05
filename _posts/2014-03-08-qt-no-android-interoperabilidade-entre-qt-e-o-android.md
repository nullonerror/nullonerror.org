---
layout: post
title: >
  Qt no Android? Interoperabilidade entre Qt e o Android
---

Como alguns de vocês sabem, tenho cada vez mais me aprofundado no desenvolvimento mobile, usando os mais variados SDKs. Recentemente precisei integrar a SDK da [RevMob](https://www.revmobmobileadnetwork.com) num projeto mobile usando [Qt](http://qt-project.org/); hoje irei cobrir apenas o Android, mas em breve postarei como fiz o mesmo para iOS.

Como podemos ver na página da [SDK da RevMov](http://sdk.revmobmobileadnetwork.com), temos suporte a diversas plataformas, bibliotecas e frameworks, mas não para o Qt. #chatiado

Minha primeira tentativa consistiu em desenvolver uma SDK do zero, a partir da versão em javascript, porém notei que estaria reinventando a roda, e que levaria muito mais tempo; por outro lado teria apenas uma base de código para iOS, Android, Desktop e o que mais o Qt suportar.

Resolvi recomeçar pela versão em Android. Baixei o [SDK para Android](http://sdk.revmobmobileadnetwork.com/android.html#download), pacote onde temos a documentação, um exemplo e um arquivo jar, que é a RevMob SDK propriamente dita.

Eis que começa a aventura! Olhando o exemplo e a documentação, o primeiro passo é instanciar a classe RevMob usando o método start, que recebe uma instância de [Activity](https://developer.android.com/reference/android/app/Activity.html) do Android em Java, como pode ser visto abaixo:

`public static RevMob start(android.app.Activity activity)`

Já temos um problema: o Qt é um framework em C++. Embora existam as classes como a [QAndroidJniObject](http://qt-project.org/doc/qt-5/qandroidjniobject.html) e [QAndroidJniEnvironment](http://qt-project.org/doc/qt-5/qandroidjnienvironment.html), que nos ajudam na interoperabilidade, abstraindo as chamadas de funções e conversões de tipos usando o [JNI](http://developer.android.com/training/articles/perf-jni.html), era preciso a instância de alguma Activity.

É sabido que toda aplicação para Android deve ter um [AndroidManifest.xml](http://developer.android.com/guide/topics/manifest/manifest-intro.html) e que deve ter pelo menos uma Activity. E onde estaria esse código que magicamente aparecia durante as etapas de compilação? Infelizmente isto ainda não é muito bem documentado no Qt (ou acabei passando batido :P). De qualquer forma precisava adicionar uma Activity customizada e alterar o AndroidManifest.xml.

Depois de uma breve pesquisa no diretório de instalação do Qt, encontrei o seguinte caminho:

`$QTDIR/5.*.*/android_(armv5|android_armv7|android_x86)/src/android/java`

* $QTDIR _O diretório raiz_
* 5.\*.\* _A versão_
* android_(armv5 \| android_armv7 \| android_x86) _A arquitetura_

É onde tem exatamente o que precisava, o AndroidManifest.xml, version.xml, os diretórios src e res. E o que temos dentro de `_src/org/qtproject/qt5/android/bindings_`? Temos QtActivity QtApplication, que herdam Activity e Application do Android SDK respectivamente, e como podemos ver, no AndroidManifest.xml

``` xml
<application android:hardwareAccelerated="true" android:name="org.qtproject.qt5.android.bindings.QtApplication" android:label="@string/app_name">

  <activity android:configChanges="orientation|uiMode|screenLayout|screenSize..."
    android:name="org.qtproject.qt5.android.bindings.QtActivity"
                  android:label="@string/app_name"
                  android:screenOrientation="unspecified">

  ...
</application>
```

Agora que temos quase tudo que precisamos, só é preciso descobrir como colocar toda essa tranqueira na hora do deploy. Lendo a documentação, descobri a variável [ANDROID_PACKAGE_SOURCE_DIR](http://qt-project.org/doc/qt-5/deployment-android.html#qmake-variables), que faz justamente o que precisava, então copiei o AndroidManifest.xml do Qt para o diretório android-sources e adicionei a seguinte entrada no .pro do projeto

`ANDROID_PACKAGE_SOURCE_DIR = $$PWD/android-sources`

Para poder usar as classes QAndroidJniObject e QAndroidJniEnvironment é necessário adicionar androidextras à variável QT

`QT += core gui widgets androidextras`

Precisamos de algumas customizações no AndroidManifest.xml; uma delas é para adicionar a FullscreenActivity do RevMob:

``` xml
<application ...>
  <activity android:name="com.revmob.ads.fullscreen.FullscreenActivity"
            android:theme="@android:style/Theme.Translucent"
            android:configChanges="keyboardHidden|orientation">
  </activity>

  ...
</application>
```

Lembram que era preciso a instância de uma activity? Para isto criei um wrapper, No diretório _android-sources_, criei a estrutura de diretórios _src/com/revmob_ e dentro um arquivo com o nome _RevMobActivity.java_, com o seguinte conteúdo:

``` java
package com.revmob;

import org.qtproject.qt5.android.bindings.QtActivity;
import com.revmob.RevMob;
import com.revmob.RevMobTestingMode;
import com.revmob.client.RevMobClient;
import android.util.Log;
import android.app.Activity;
import java.lang.String;

public class RevMobActivity extends QtActivity {

  private static Activity activity;

  public RevMobActivity() {
    activity = this;
  }

  public static void startSession(String appId) {
    RevMobClient.setSDKName("qt-android");
    RevMobClient.setSDKVersion("0.0.1");
    RevMob.start(activity, appId);
  }

  public static void showFullscreen() {
    RevMob revmob = RevMob.session();
    revmob.showFullscreen(activity);
  }

  // ...
}
```

E apontamos essa nova classe no _AndroidManifest.xml_, substituindo `org.qtproject.qt5.android.bindings.QtActivity` por `com.revmob.RevMobActivity`. Com isto, o Android passa a instanciar a classe customizada ao invés da classe do Qt, e finalmente temos um _wrapper_.

Para finalizar esta etapa precisamos adicionar o arquivo revmob-6.8.2.jar da SDK do RevMob no diretório libs, ainda dentro de android-sources.

Finalmente poderemos voltar à programação de verdade, C++ :)

Para começar a utilizar precisamos iniciar uma sessão, o que pode ser feito na inicializacão do app, da seguinte maneira:

``` cpp
QString appId = "";

QAndroidJniObject param = QAndroidJniObject::fromString(appId);
QAndroidJniObject::callStaticMethod<void>("com/revmob/RevMobActivity",
                                          "startSession",
                                          "(Ljava/lang/String;)V",
                                          param.object<jstring>());
```

Onde appId é um código fornecido pela RevMob que identifica sua app.

Para mostrar um banner em FullScreen é bem simples - só precisamos invocar aquele método showFullscreen que foi criado logo acima, assim:

`QAndroidJniObject::callStaticMethod<void>("com/revmob/RevMobActivity", "showFullscreen");`

O trecho acima invoca um método em Java da classe RevMobActivity, responsável por carregar e exibir um anúncio em fullscreen.

É muito legal poder rodar meus projetos em Qt no meu celular, apenas recompilando, e mais legal ainda saber que posso acessar recursos da SDK do Android de forma semi transparente...
