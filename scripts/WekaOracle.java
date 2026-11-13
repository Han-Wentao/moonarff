// Independent test adapter. Apache-2.0; Weka is an external GPL-3.0 test runtime.
import weka.core.*;
import weka.core.converters.ArffLoader.ArffReader;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.io.*;
import java.util.*;

public class WekaOracle {
  static String q(String s) {
    StringBuilder b = new StringBuilder("\"");
    for (int i=0;i<s.length();i++) {
      char c=s.charAt(i);
      switch(c) {
        case '"': b.append("\\\""); break;
        case '\\': b.append("\\\\"); break;
        case '\n': b.append("\\n"); break;
        case '\r': b.append("\\r"); break;
        case '\t': b.append("\\t"); break;
        default: if(c<32)b.append(String.format("\\u%04x",(int)c));else b.append(c);
      }
    }
    return b.append('"').toString();
  }
  static String attrs(Instances d) {
    StringJoiner out=new StringJoiner(",","[","]");
    for(int c=0;c<d.numAttributes();c++) {
      Attribute a=d.attribute(c);
      String kind;
      if(a.isDate())kind="[\"date\","+q(a.getDateFormat())+"]";
      else if(a.isRelationValued())kind="[\"relation\","+attrs(a.relation())+"]";
      else if(a.isNominal()) {
        StringJoiner labels=new StringJoiner(",","[","]");
        for(int i=0;i<a.numValues();i++)labels.add(q(a.value(i)));
        kind="[\"nominal\","+labels+"]";
      } else kind=q(a.isNumeric()?"numeric":"string");
      out.add("["+q(a.name())+","+kind+"]");
    }
    return out.toString();
  }
  static String rows(Instances d) {
    StringJoiner out=new StringJoiner(",","[","]");
    for(Instance r:d) {
      StringJoiner cells=new StringJoiner(",","[","]");
      for(int c=0;c<d.numAttributes();c++) {
        Attribute a=d.attribute(c);
        if(r.isMissing(c))cells.add("null");
        else if(a.isRelationValued())cells.add(rows(r.relationalValue(c)));
        else if(a.isNumeric()||a.isDate())cells.add(Double.toString(r.value(c)));
        else cells.add(q(r.stringValue(c)));
      }
      out.add("["+r.weight()+","+cells+"]");
    }
    return out.toString();
  }
  static String canonical(Instances d) {
    return "["+q(d.relationName())+","+attrs(d)+","+rows(d)+"]";
  }
  public static void main(String[] args) throws Exception {
    TimeZone.setDefault(TimeZone.getTimeZone("UTC")); Locale.setDefault(Locale.ROOT);
    Path input=Paths.get(args[0]), output=Paths.get(args[1]);
    Files.createDirectories(output);
    List<Path> paths=new ArrayList<>();
    try(var stream=Files.list(input)){stream.filter(p->p.toString().endsWith(".arff")).sorted().forEach(paths::add);}
    for(Path path:paths) {
      Instances full;
      try(Reader r=Files.newBufferedReader(path,StandardCharsets.UTF_8)){full=new Instances(r);}
      try(Reader r=Files.newBufferedReader(path,StandardCharsets.UTF_8)) {
        ArffReader incremental=new ArffReader(r,1);
        Instances parsed=incremental.getStructure();
        Instance next;
        while((next=incremental.readInstance(parsed))!=null)parsed.add(next);
        if(!canonical(full).equals(canonical(parsed)))throw new AssertionError("Weka incremental mismatch: "+path);
      }
      String base=path.getFileName().toString().replace(".arff","");
      Files.writeString(output.resolve(base+".json"),canonical(full),StandardCharsets.UTF_8);
      Files.writeString(output.resolve(base+".arff"),full.toString(),StandardCharsets.UTF_8);
    }
    System.out.println("Weka 3.8.6: "+paths.size()+" full/incremental parses and serializations");
  }
}
