#!/bin/sh

sleep 3s

# Указываем путь к log-файлу
log="/var/log/vpn_status.log"

# Задаем периодичность опроса шлюзов.
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
    prefered_gw=${ovpn}
    dev_ovpn="tun0"

    ovpn=`ifconfig ${dev_ovpn} | awk -F ' *|:' '/inet addr/{print $4}'`

# Текущие статусы шлюзов: 0 - шлюз недоступен, 1 - шлюз работает
    gw1_curr_status=0

# Текущие потери пакетов на шлюзе
    gw1_curr_packet_loss=0

# Максимальный процент потерь пакетов, при превышении данного числа, шлюз считается недоступным
    gw1_max_packet_loss=35

# Отчищаем log-файл и сохраняем значения основных переменных
    clear_log
    echo `date +"%T %d.%m.%Y"`." Init environment OK. Check gateways status every ${check_period}." >> ${log}
    echo `date +"%T %d.%m.%Y"`." ISP1 [ovpn=${ovpn}, dev_ovpn=${dev_ovpn}, ovpn=${ovpn}]" >> ${log}
}

# Данная функция определяет текущее состояние каждого из шлюзов.
# Если текущий процент потерь меньше максимально допустимого, то считаем, что шлюз доступен.
get_current_status ()
{
    echo `date +"%T %d.%m.%Y"`." Get current status ISP gateways." >> ${log}

###################
##    dev_tun=`ifconfig | grep tun0 | awk '{print $1}'`
##    if [ "${dev_tun}" == "tun0" ]
##    then
##        echo "OK"
##    echo "${dev_tun}"
##    else
##        echo "BAD"
##    echo ${dev_tun}
##    fi
###################

# Get current status default gateway ISP1/Проверяем пинги до DNS Google
    dev_tun=`ifconfig | grep tun0 | awk '{print $1}'`
    ovpn_curr_packet_loss=`ping -I ${dev_ovpn} -c20 -l20 -q -W3 ${dns1} | grep loss | awk '{print $(NF-4)}' | cut -d"%" -f1`

    if [ ${ovpn_curr_packet_loss} -le ${gw1_max_packet_loss} -a "${dev_tun}" = "tun0" ]
    then
        echo `date +"%T %d.%m.%Y"`. "ISP1. [STATUS - OK]. Current packet loss on ${ovpn} via ${dev_ovpn} is ${gw1_curr_packet_loss}%. And ${dev_tun} is up" >> ${log}
        gw1_curr_status=1
    else
        echo `date +"%T %d.%m.%Y"`. "ISP1. [STATUS - CRITICAL]. Current packet loss on ${ovpn} via ${dev_ovpn} is ${gw1_curr_packet_loss}%. And tun0 is down" >> ${log}
        gw1_curr_status=0
    fi
}
# Данная функция производит переключение шлюза по умолчанию в зависимости от результатов полученных в get_current_status ()
# На данный момент предпочитаемым шлюзом может быть только ${gw1}
switch_default_gw ()
{
    curr_ovpn=`ip route show | grep tun0 | grep --invert-match proto | grep 0.0.0.0/1 | awk '{print $3}'`
    if [ ${curr_ovpn} = ${prefered_gw} -a ${gw1_curr_status} -eq 1 ]
    then
        echo `date +"%T %d.%m.%Y"`. "[STATUS - OK]. Current default gateway is prefered and running up. Nothing to do." >> ${log}
        return
    fi

    if [ ${gw1_curr_status} -eq 0 ]
    then
        echo "**************************************************************************" >> ${log}
        echo `date +"%T %d.%m.%Y"`. "CRITICAL. OpenVPN gateway is down. Restart OpenVPN." >> ${log}
        echo "**************************************************************************" >> ${log}
	/etc/init.d/openvpn restart
        return
    fi
}

# Инициализируем переменные
init

# "Заходим" в вечный цикл, в котором по очереди вызываем функции get_current_status () и switch_default_gw ()
# После этого делаем паузу, время паузы задается в переменной ${check_period}
while [ 1 ]
do
    get_current_status
    switch_default_gw
    sleep ${check_period}
done
