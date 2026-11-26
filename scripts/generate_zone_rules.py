#!/usr/bin/env python3
"""Reproduce the deterministic Java 17.0.2 / tzdb 2021e compatibility snapshot.

Queries timezone facts, not implementation source. JDK reflection is used only
by this developer tool to enumerate candidate change instants; actual offsets
come from ZoneInfo.getOffsetsByWall. No Java dependency is shipped at runtime.
"""
import json, re, subprocess, tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
JAVA = r'''import java.util.*; import java.io.*; import java.lang.reflect.*;
public class ExportZoneRules {
 public static void main(String[] args) throws Exception {
  if (!System.getProperty("java.version").equals("17.0.2")) throw new IllegalStateException("Requires Java 17.0.2");
  if (!java.time.zone.ZoneRulesProvider.getVersions("UTC").lastKey().equals("2021e")) throw new IllegalStateException("Requires tzdb 2021e");
  Class<?> c=Class.forName("sun.util.calendar.ZoneInfo");
  Field tf=c.getDeclaredField("transitions"), of=c.getDeclaredField("offsets"); tf.setAccessible(true); of.setAccessible(true);
  Method wall=c.getMethod("getOffsetsByWall",long.class,int[].class);
  Method utc=c.getMethod("getOffsets",long.class,int[].class);
  BufferedReader in=new BufferedReader(new InputStreamReader(System.in)); String id;
  while((id=in.readLine())!=null) {
   TimeZone z=TimeZone.getTimeZone(id); if(!z.getID().equals(id)) throw new IllegalStateException(id);
   int[] out=new int[2]; long[] ts=(long[])tf.get(z); int[] os=(int[])of.get(z);
   wall.invoke(z,-62135769600000L,out); int initial=out[0]; int prev=initial; int prevDST=out[1];
   int autoMask=0;
   for(String[] row:java.text.DateFormatSymbols.getInstance(Locale.US).getZoneStrings()) if(row[0].equals(id)) {
    for(int k=1;k<=2;k++) if(row[k].equalsIgnoreCase(row[k+2])) autoMask|=1<<k;
    break;
   }
   List<String> events=new ArrayList<>(), utcEvents=new ArrayList<>();
   utc.invoke(z,-62135769600000L,out); int utcInitial=out[0], utcPrev=out[0], utcDST=out[1];
   if(ts!=null) for(long t:ts) {
    long u=t>>12; utc.invoke(z,u,out);
    if(out[0]!=utcPrev || out[1]!=utcDST) {
     utcEvents.add(u+","+out[0]+","+out[1]); utcPrev=out[0]; utcDST=out[1];
    }
   }
   String[] labels=null;
   for(String[] row:java.text.DateFormatSymbols.getInstance(Locale.US).getZoneStrings()) if(row[0].equals(id)) { labels=Arrays.copyOfRange(row,1,5);break; }
   if(labels==null) throw new IllegalStateException(id);
   if(ts!=null) for(long t:ts) {
    long w=(t>>12)+os[(int)(t&15)]; wall.invoke(z,w,out);
    // A zone with no modern saving must still infer historical daylight time
    // for a daylight label (SimpleDateFormat deliberately leaves DST unset).
    int dst=z.getDSTSavings()==0?out[1]:0;
    if(out[0]!=prev || dst!=prevDST) {events.add(w+","+out[0]+","+dst);prev=out[0];prevDST=dst;}
   }
   System.out.println(id+"\t"+initial+"\t"+z.getDSTSavings()+"\t"+autoMask+"\t"+String.join(";",events)+"\t"+utcInitial+"\t"+String.join(";",utcEvents)+"\t"+String.join("|",labels));
  }
 }
}'''
def generate():
 source=(ROOT/'date_zone.mbt').read_text(encoding='utf-8')
 ids=sorted(set(re.findall(r'\(\"(?:\\.|[^\"])*\",\s*-?\d+,\s*\d+,\s*\"([^\"]+)\",',source)))
 with tempfile.TemporaryDirectory() as td:
  f=Path(td)/'ExportZoneRules.java';f.write_text(JAVA,encoding='utf-8')
  subprocess.run(['javac',str(f)],check=True)
  data=subprocess.run(['java','-Dfile.encoding=UTF-8','--add-opens=java.base/sun.util.calendar=ALL-UNNAMED','-cp',td,'ExportZoneRules'],input='\n'.join(ids)+'\n',text=True,encoding='utf-8',stdout=subprocess.PIPE,check=True).stdout
 events=[]; meta=[]; masks=[]; labels=[]; utc_events=[]; utc_meta=[]
 for line in data.splitlines():
  id,initial,saving,mask,ev,ui,ue,names=line.split('\t'); start=len(events); masks.append(int(mask))
  labels.append(names.split('|'))
  us=len(utc_events)
  if ue: utc_events.extend(tuple(map(int,e.split(','))) for e in ue.split(';'))
  utc_meta.append((int(ui)//1000,us,len(utc_events)-us))
  if ev: events.extend(tuple(map(int,e.split(','))) for e in ev.split(';'))
  meta.append((int(initial)//1000,int(saving)//1000,start,len(events)-start))
 lines=['///|','/// Generated timezone facts: Java 17.0.2, IANA tzdb 2021e (public domain).','/// Regenerate using scripts/generate_zone_rules.py; see SOURCES.md.','let date_zone_rule_ids : Array[String] = [']
 lines += ['  '+json.dumps(id)+',' for id in ids];lines+= [']','','///|','/// (initial raw seconds, modern saving seconds, event start, event count).','let date_zone_rule_meta : Array[(Int32, Int32, Int32, Int32)] = [']
 lines += ['  '+str(m)+',' for m in meta];lines += [']','','///|','/// (local-wall epoch milliseconds, raw seconds, inferred daylight seconds).','let date_zone_rule_events : Array[(Double, Int32, Int32)] = [']
 lines += [f'  ({t}.0, {raw//1000}, {dst//1000}),' for t,raw,dst in events];lines += [']','']
 lines += ['///|', 'let date_zone_auto_masks : Array[Int32] = [' + ', '.join(map(str, masks)) + ']','']
 lines += ['///|','/// (UTC initial raw seconds, event start, event count).','let date_zone_utc_meta : Array[(Int32, Int32, Int32)] = [']
 lines += ['  '+str(m)+',' for m in utc_meta];lines += [']','','///|','/// (UTC epoch milliseconds, raw seconds, daylight seconds).','let date_zone_utc_events : Array[(Double, Int32, Int32)] = [']
 lines += [f'  ({t}.0, {raw//1000}, {dst//1000}),' for t,raw,dst in utc_events];lines += [']','']
 lines += ['///|','/// Locale.US labels in JDK match order, indexed by date_zone_rule_ids.','let date_zone_rule_names : Array[Array[String]] = [']
 lines += ['  '+json.dumps(n,ensure_ascii=False)+',' for n in labels]; lines += [']','']
 (ROOT/'date_zone_rules.mbt').write_text('\n'.join(lines),encoding='utf-8')
 print(f'Generated {len(ids)} zones, {len(events)} offset changes')
if __name__=='__main__': generate()
