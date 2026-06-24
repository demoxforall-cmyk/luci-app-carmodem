#!/usr/bin/env python3
# Прототип парсера +QENG="servingcell" для RM520N-GL (режим LTE)
import re

# 3GPP индекс ширины канала -> МГц
BW = {0:"1.4",1:"3",2:"5",3:"10",4:"15",5:"20"}

def parse_servingcell_lte(line):
    m = re.search(r'\+QENG:\s*"servingcell",(.+)', line.strip())
    if not m:
        return None
    f = [x.strip().strip('"') for x in m.group(1).split(',')]
    # Поля LTE: state,rat,duplex,MCC,MNC,cellID,PCI,EARFCN,band,ULbw,DLbw,TAC,RSRP,RSRQ,RSSI,SINR,CQI,txpwr,srxlev
    state,rat,duplex = f[0],f[1],f[2]
    mcc,mnc = f[3],f[4]
    cellid_hex = f[5]
    cellid = int(cellid_hex,16)
    pci = int(f[6]); earfcn=int(f[7]); band=int(f[8])
    dlbw = BW.get(int(f[10]),"?")
    tac_hex = f[11]; tac = int(tac_hex,16)
    def num(x): return None if x in ('-','') else int(x)
    rsrp,rsrq,rssi,sinr = num(f[12]),num(f[13]),num(f[14]),num(f[15])
    return {
        "state":state,"rat":rat,"duplex":duplex,
        "plmn":f"{mcc}{mnc}","mcc":mcc,"mnc":mnc,
        "cell_id_raw":cellid_hex,"cell_id":cellid,
        "enb":cellid//256,"local_cell":cellid%256,
        "pci":pci,"earfcn":earfcn,"band":f"B{band}","bw_mhz":dlbw,
        "tac_raw":tac_hex,"tac":tac,
        "rsrp":rsrp,"rsrq":rsrq,"rssi":rssi,"sinr":sinr,
    }

# прогон на реальной фикстуре
line = open(__import__("os").path.join(__import__("os").path.dirname(__file__),"fixtures","servingcell_lte.txt")).read().strip()
r = parse_servingcell_lte(line)
print("Вход :", line)
print("Разбор:")
for k,v in r.items():
    print(f"  {k:12} = {v}")
