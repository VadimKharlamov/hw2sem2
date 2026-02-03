Харламов Вадим Сергеевич БПИ225

Задание на 6-8 баллов:

Для запуска кластера и развертывания приложения необходимо:

Поднять docker с postgres через `docker compose up -d`

Для запуска приложения из папки muffin-wallet и muffin-currency вызвать сборку через `helmfile sync`

Запустить туннель:

minikube addons enable ingress

sudo minikube tunnel

Запустить loki + promtail + grafana

helm upgrade --install loki grafana/loki-stack \
  --namespace logging \
  --create-namespace \
  --set promtail.enabled=true \
  --set grafana.enabled=true \
  --set loki.persistence.enabled=false \
  --set "promtail.config.clients[0].url=http://loki.logging.svc.cluster.local:3100/loki/api/v1/push"

helm upgrade --install loki grafana/loki \      
  --namespace logging \
  --create-namespace \
  -f promtail.yaml    

Пароль от графаны можно узнать так

kubectl get secret --namespace logging loki-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode ; echo

Запустить zipkin

helm repo add openzipkin https://openzipkin.github.io/zipkin

helm repo update

helm install zipkin openzipkin/zipkin \
  --namespace observability \
  --create-namespace

Для доступа к UI выполнить

`kubectl port-forward svc/loki-grafana 3000:80 -n logging` # Для графаны

`kubectl port-forward -n observability svc/zipkin 9411:9411` # Для зипкина

Проверка что компоненты системы работоспособны:

`docker ps` - для проверки состояния контейнера с postgres

`kubectl get pods` (контексты: default, logging, observability) - для проверки что поды с приложением поднялись

Правки в исходном коде сервисов:

Так как мы все разворачиваем в Kubernetes, а в исходном коде трейсы идут на localhost, поправим хосты

В muffin-currency просто передадим в `initTracing` наш url

`initTracing("currency-service", "http://zipkin.observability.svc.cluster.local:9411/api/v2/spans")`

В muffin-wallet добавим новый env 
`MANAGEMENT_ZIPKIN_TRACING_ENDPOINT` с этим же url'ом

Также я поправил muffin-currency так как в текущей реализации он не брал родительский трейс о создавал всегда новый

Вот отрывок кода
```
func tracingMiddleware(next http.Handler) http.Handler {
  return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
    // Start a new span for this request
    span := tracer.StartSpan(r.URL.Path, 
      zipkin.Kind(model.Server),
      zipkin.RemoteEndpoint(nil),
    )
    defer span.Finish()
    
    // Add span to context
    ctx := zipkin.NewContext(r.Context(), span)
    
    // Add HTTP tags to span
    span.Tag("http.method", r.Method)
    span.Tag("http.url", r.URL.String())
    span.Tag("http.path", r.URL.Path)
    span.Tag("component", "http")
    
    // Get trace ID for logging and metrics
    traceID := span.Context().TraceID.String()
```

Тут мы создаем новый спан по пути, который перехватил mw, а потом по этому спану строим traceID. Но в случае если к нам приходит запрос от muffin-wallet у запроса уже есть traceID и мы должны его использовать поэтому я через `"github.com/openzipkin/zipkin-go/propagation/b3"` добавил вот такой экстракт
```
    sc := tracer.Extract(b3.ExtractHTTP(r))

    var span zipkin.Span
    if sc.TraceID.High != 0 || sc.TraceID.Low != 0 {
      span = tracer.StartSpan(
        r.URL.Path,
        zipkin.Kind(model.Server),
        zipkin.Parent(sc),
      )
    } else {
      span = tracer.StartSpan(
        r.URL.Path,
        zipkin.Kind(model.Server),
      )
    }

    defer span.Finish()
```
то есть если у нас уже пришел какой-то traceID, то мы его используем, иначе создаем новый (если например кто-то напрямую дернул ручку)

На стороне muffin-wallet достаточно добавить env `MANAGEMENT_TRACING_PROPAGATION_TYPE` и поставить `B3` 

Все новые версии разместил у себя docker hub:
1. kharlamovvadim/muffin-wallet
2. kharlamovvadim/muffin-currency

Как посмотреть логи/трейсы:

Заходим в графану (http://localhost:3000) и строим дашборд с data source - Loki (если ставить через loki-stack то source будет уже проставлен в коннектах)

Для быстрого переключения добавил переменные LEVEL и TraceID

В Loki query указываем, таким образом вы вытащим нужные нам label для фильтрации по уровню логов и traceID

`{app="muffin-wallet", logLevel = "$LEVEL"}`

![](/img/loki1.png "")

Для смены например на WARN логи просто меняем level 

![](/img/loki2.png "")

Для muffin-currency аналогично

`{app="muffin-currency", logLevel = "$LEVEL"}`

![](/img/loki3.png "")

и аналогично может смотреть по уровню логов через переменные

![](/img/loki_ex.png "")

Таким образом получаем такие дашборды с возможностью фильтра по уровню лога

![](/img/loki4.png "")

Трейсы можно смотреть в zipkin

![](/img/zip1.png "")

Сделаем тразакцию, которая создаст нам 3 спана через соотвествующую ручку
```
http://muffin-wallet.com/v1/muffin-wallet/e7374ea8-329c-4cb8-98d5-524167a0220a/transaction
```
```
{
  "to_muffin_wallet_id": "f96f0dec-42b5-4fe8-ae41-5d1884aa18e0",
  "amount": 77
}
```


Первый и второй от muffin-wallet, о хэндле запроса от юзера и отправки запроса в muffin-currency, третий от muffin-currency, о текущем рейте

![](/img/zip3.png "")
![](/img/zip4.png "")

Можем также добавить в графане новый data source и посмотреть на определенные трейсы

![](/img/zip5.png "")

По параметру traceID также можно найти соотвествующие логи в обеих сервисах для этого подготовлены еще два дашборда, который помимо уровня учитывают traceID

![](/img/zip6.png "")

Как мы видим это логи одного трейса

![](/img/zip7.png "")

Помимо стандартных лейблов собираем уровень логов и traceID/spanId

![](/img/label1.png "")

![](/img/label2.png "")

и используем запросы

`{app="muffin-currency", logLevel = "$LEVEL", traceId = "$TraceID"}`

`{app="muffin-wallet", logLevel = "$LEVEL", traceId = "$TraceID"}`

Все логи/трейсы тестировались на ручках

http://muffin-wallet.com/v1/muffin-wallets

http://muffin-currency.com/rate?from=CARAMEL&to=PLAIN

http://muffin-wallet.com/v1/muffin-wallet/{id}/transaction

Спасибо за внимание

