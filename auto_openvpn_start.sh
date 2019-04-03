#!/bin/sh

sleep 20s

# Указываем путь к log-файлу
log="/var/log/vpn_status.log"

# Задаем периодичность опроса OpenVPN шлюза.
# 30s - 30 секунд
# 10m - 10 минут
# 1h - 1 час
check_period="30s"

# Если log-файл не найден, создаем его, иначе отчищаем
clear_log ()
{
if [ ! -f ${log} ]
then
    touch ${log}
else
    cat /dev/null > ${log}
fi
}

# Инициализируем переменные
init ()
{
    dns1="8.8.8.8"
    ovpn="10.8.0.1"
    dev_ovpn="tun0"

# Текущие потери пакетов на шлюзе
    ovpn_curr_packet_loss=0

# Максимальный процент потерь пакетов, при превышении данного числа, шлюз считается недоступным
    gw1_max_packet_loss=35

# Отчищаем log-файл и сохраняем значения основных переменных
    clear_log
    echo `date +"%T %d.%m.%Y"`." Init environment OK. Check OpenVPN status every ${check_period}." >> ${log}
    echo `date +"%T %d.%m.%Y"`." [OpenVPN server IP = ${ovpn}, Google DNS = ${dns1}]." >> ${log}
}

# Данная функция определяет текущее состояние OpenVPN шлюза.
# Если текущий процент потерь меньше максимально допустимого, то считаем, что шлюз доступен.
get_current_status ()
{
    echo `date +"%T %d.%m.%Y"`." Get current status OpenVPN gateways." >> ${log}

# Проверяем интерфейс tun0, если ОК, то проверяем пинги до DNS от Google, иначе перезапускаем OpenVPN на клиенте.

dev_tun=`ifconfig | grep tun0 | awk '{print $1}'`
if [ "${dev_tun}" = "tun0" ]
then

# Проверяем пинги до DNS Google и наличие интерфейса tun0, если ОК - ничего не меняем, иначе перезапускаем OpenVPN на клиенте.

ovpn_curr_packet_loss=`ping -I ${dev_ovpn} -c20 -l20 -q -W3 ${dns1} | grep loss | awk '{print $(NF-4)}' | cut -d"%" -f1`
    if [ ${ovpn_curr_packet_loss} -le ${gw1_max_packet_loss} -a "${dev_tun}" = "tun0" ]
    then
        echo `date +"%T %d.%m.%Y"`. "OpenVPN: [STATUS - OK]. Current OpenVPN gateway running up. Nothing to do." >> ${log}
    else
        echo "******************************************************************************************************************************************************************" >> ${log}
        echo `date +"%T %d.%m.%Y"`. "OpenVPN: [STATUS - CRITICAL]. Current packet loss on ${ovpn} via ${dev_ovpn} is ${ovpn_curr_packet_loss}%. But tun0 is UP. Restart OpenVPN." >> ${log}
        echo "******************************************************************************************************************************************************************" >> ${log}
    /etc/init.d/openvpn restart
    fi
else
    echo "***************************************************************" >> ${log}
    echo `date +"%T %d.%m.%Y"`. "CRITICAL. tun0 is DOWN. Restart OpenVPN." >> ${log}
    echo "***************************************************************" >> ${log}
    /etc/init.d/openvpn restart
fi

}

# Инициализируем переменные
init

# "Заходим" в вечный цикл, в котором вызываем функцию get_current_status ()
# После этого делаем паузу, время паузы задается в переменной ${check_period}
while [ 1 ]
do
    get_current_status
    sleep ${check_period}
done
