#!/bin/sh

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
    gw1="10.8.0.1"
    prefered_gw=${gw1}

    dev_if1="ens160"

    if1=`ifconfig ${dev_if1} | awk -F ' *|:' '/inet addr/{print $4}'`

# Текущие статусы шлюзов: 0 - шлюз недоступен, 1 - шлюз работает
    gw1_curr_status=0

# Текущие потери пакетов на шлюзе
    gw1_curr_packet_loss=0

# Максимальный процент потерь пакетов, при превышении данного числа, шлюз считается недоступным
    gw1_max_packet_loss=35

# Отчищаем log-файл и сохраняем значения основных переменных
    clear_log
    echo `date +"%T %d.%m.%Y"`." Init environment OK. Check gateways status every ${check_period}." >> ${log}
    echo `date +"%T %d.%m.%Y"`." ISP1 [if1=${if1}, dev_if1=${dev_if1}, gw1=${gw1}]" >> ${log}
}

# Данная функция определяет текущее состояние каждого из шлюзов.
# Если текущий процент потерь меньше максимально допустимого, то считаем, что шлюз доступен.
get_current_status ()
{
    echo `date +"%T %d.%m.%Y"`." Get current status ISP gateways." >> ${log}

# Get current status default gateway ISP1/Проверяем пинги до DNS Google
#   gw1_curr_packet_loss=`ping -I ${dev_if1} -c20 -l20 -q -W3 ${gw1} | grep loss | awk '{print $(NF-4)}' | cut -d"%" -f1`
    gw1_curr_packet_loss=`ping -I tun0 -c20 -l20 -q -W3 8.8.8.8 | grep loss | awk '{print $(NF-4)}' | cut -d"%" -f1`
#    dev_tun=`ifconfig | grep tun0 | awk '{print $1}'`

    if [ ${gw1_curr_packet_loss} -le ${gw1_max_packet_loss} ]
    then
        echo `date +"%T %d.%m.%Y"`. "ISP1. [STATUS - OK]. Current packet loss on ${gw1} via ${dev_if1} is ${gw1_curr_packet_loss}%." >> ${log}
        gw1_curr_status=1
    else
        echo `date +"%T %d.%m.%Y"`. "ISP1. [STATUS - CRITICAL]. Current packet loss on ${gw1} via ${dev_if1} is ${gw1_curr_packet_loss}%." >> ${log}
        gw1_curr_status=0
    fi

# Данная функция производит переключение шлюза по умолчанию в зависимости от результатов полученных в get_current_status ()
# На данный момент предпочитаемым шлюзом может быть только ${gw1}
switch_default_gw ()
{
    curr_gw=`ip route show | grep default | awk '{print $3}'`
    if [ ${curr_gw} = ${prefered_gw} -a ${gw1_curr_status} -eq 1 ]
    then
        echo `date +"%T %d.%m.%Y"`. "[STATUS - OK]. Current default gateway is prefered and running up. Nothing to do." >> ${log}
        return
    fi

    if [ ${curr_gw} = ${prefered_gw} -a ${gw1_curr_status} -eq 0 ]
    then
        echo `date +"%T %d.%m.%Y"`. "Prefered gw ${gw1} is down. Change default gw to ${gw2}" >> ${log}
        echo `date +"%T %d.%m.%Y"`. "ip route replace default via ${gw2} dev ${dev_if2}" >> ${log}
        /sbin/ip route replace default via ${gw2} dev ${dev_if2}
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
