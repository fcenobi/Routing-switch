# Routing-switch

Автоматическое переключение каналов

Ведение

Рано или поздно практически каждый системный администратор сталкивается с задачей использования 2х и более каналов и автоматического переключения
маршрутизации при падении одного из них на резервный канал.
К сожалению на linux нет т.н. продакшен решения для решения этой задачи. Единственное решения - это использование протоколов динамической
маршрутизации таких как BGP, который в свою очередь требует наличия AS. Что к сожалению не всегда возможно чисто технически и экономически.
Поэтому и приходится обходить эти моменты по другому.

Итак рассмотрим классический случай. Есть шлюз на базе GNU Linux, к которому одновременно подключены 2 интернет провайдера.
Наша задача - при падении основного шлюза, переключать автоматически всех на резервный канал, а после восстановления делать обратную операцию.

Для этого будем использовать небольшой скрипт. Принцип его очень простой. Раз в n минут мы проверяем доступность шлюза провайдера с помощью утилиты ping.
И если основной шлюз не доступен или процент потерь пакетов больше заданного порога, то мы меняем шлюз по умолчанию на резервный.
После переключения на резервный канал мы также продолжаем проверять доступность основного шлюза и после того, как он снова станет доступным снова
переключаемся на него.


Примечание
Данный скрипт не будет работать на FreeBSD, так как используется утилита ip. 
Но вам никто не мешает и не запрещает доработать скрипт и заменить вызов ip на команды, которые доступны в вашем дистрибутиве.


Источник:
http://sys-adm.org.ua/net/routing
