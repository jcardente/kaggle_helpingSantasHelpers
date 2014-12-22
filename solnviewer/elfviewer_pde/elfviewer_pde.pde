import controlP5.*;
import java.text.SimpleDateFormat;
import java.util.Date;


class Job {
 int elfid;
 int start_minute;
 int duration;
 
 Job(int _elfid, int _start_minute, int _duration) {
    elfid        = _elfid;
    start_minute = _start_minute;
    duration     = _duration; 
 }
 
 void draw() {
   int day   = start_minute / int(24 * 60);
   int start = start_minute % int(24 * 60);

   // Need to account for long jobs lasting for multiple days
   int work_left = duration;
   while (work_left > 0) {
     int px = start;
     int py = day * 12;

     // Cut off at midnight 
     int work_end   = min(start+work_left, 1440);
     int work_today = work_end - start;

     stroke(100);
     rect(px, py, work_today, 10);
     
     work_left = work_left - work_today;
     if (work_left > 0) {
       start = 0;
       day   = day +1;
     }
   }  
}

} // end class

void OpenFile (int _value) {
   selectInput("Select a file to process:", "fileSelected");
}


void fileSelected(File selection) { 
  if (selection == null) {
   return; 
  }
  
  fileLoaded = false;
  table      = loadTable(selection.getAbsolutePath(), "header");
  
  solnJobs = new ArrayList<Job>();
  elves    = new IntList();
  SimpleDateFormat dateFormat = new SimpleDateFormat("yyyy M d H m");
  Date startDate = null;
  try {
  startDate = dateFormat.parse("2014 1 1 0 0");
  }
  catch (Exception e) {
    println(e.getMessage());
  }
  for (TableRow row : table.rows()) {
     int elfid = row.getInt("ElfId");
     String start_time = row.getString("StartTime");
     int duration = row.getInt("Duration");
     int start_minute = 0;
     
      if (! elves.hasValue(elfid)) {
         elves.append(elfid); 
       }
      
      maxElfId = max(elfid, maxElfId);
      
      Date mydate;
      try {
         mydate =  dateFormat.parse(row.getString("StartTime"));
         start_minute = int((mydate.getTime() - startDate.getTime())/(60 * 1000));
      }
       catch (Exception e) {
          println(e.getMessage()); 
      }
       
      solnJobs.add(new Job(elfid, start_minute, duration));
  }

  currentElf = 1;
  fileLoaded = true;

  Textlabel tl = (Textlabel) cp5.getController("currentFile");
  tl.setText(selection.getName());

  tl = (Textlabel) cp5.getController("currentElf");
  tl.setText(Integer.toString(currentElf));

  println("Found " + elves.size() + " elves and " + solnJobs.size() + " jobs.");
}


void keyPressed() {
  if (key == CODED) {
    if (keyCode == UP) {
      currentElf = min(currentElf + 1, maxElfId);
      
    } else if (keyCode == DOWN) {
      currentElf = max(currentElf - 1, 1);
    }
  }
}


ControlP5 cp5;
Table     table;
boolean   fileLoaded  = false;
IntList   elves;
ArrayList<Job> solnJobs = new ArrayList<Job>();
int currentElf=1;
int maxElfId = 1;
int scaleFactor = 2;


void setup() {
  
  size(750, 750, P2D);
  background(#EEEEEE);

  cp5 = new ControlP5(this);
  cp5.setColorForeground(color(140,140,140));
  cp5.setColorBackground(color(200,200,200));
  cp5.setColorActive(color(77,77,77));  
  cp5.setColorLabel(color(77,77,77)); 
  cp5.setColorValue(color(77,77,77)); 

  cp5.addButton("OpenFile")
     .setPosition(10,10)
     .setSize(50,20)
     ;
     
  cp5.addTextlabel("filename")
                   .setText("FILE:")
                   .setPosition(60,10)
                   .setColorValue(color(77,77,77))
                   .align(ControlP5.LEFT, ControlP5.BOTTOM,
                          ControlP5.LEFT, ControlP5.BOTTOM)
                    ;
   
  cp5.addTextlabel("currentFile")
                   .setText("")
                   .setPosition(90,10)
                   .setColorValue(color(77,77,77))
                   .align(ControlP5.RIGHT, ControlP5.BOTTOM,
                          ControlP5.RIGHT, ControlP5.BOTTOM)
                    ;

  cp5.addTextlabel("elfname")
                   .setText("ELF:")
                   .setPosition(60,20)
                   .setColorValue(color(77,77,77))
                   .align(ControlP5.LEFT, ControlP5.BOTTOM,
                          ControlP5.LEFT, ControlP5.BOTTOM)
                    ;
                    
  cp5.addTextlabel("currentElf")
                   .setText("")
                   .setPosition(90,20)
                   .setColorValue(color(77,77,77))
                    ;

  //cp5.addSlider("height")
  //   .setPosition(10,80)
  //   .setSize(10,600)
  //   .setRange(0,200)
  //   .setValue(128)
  //   .setVisible(true)
  //   ;
                   
  //cp5.getController("height").getValueLabel().align(ControlP5.LEFT, ControlP5.BOTTOM_OUTSIDE).setPaddingX(0);
  //cp5.getController("height").getCaptionLabel().align(ControlP5.RIGHT, ControlP5.BOTTOM_OUTSIDE).setPaddingX(0);
  //cp5.getController("height").setLabelVisible(false);
  //cp5.setAutoDraw(false);
}


void draw() {
  
  background(255);

  pushMatrix();
  translate(40,40);
  translate(-500/scaleFactor, 0);
  scale(.5);
  if (fileLoaded) {
    for (Job j: solnJobs) {
      if (j.elfid == currentElf) {
        j.draw();
      }
    }
    
    Textlabel tl = (Textlabel) cp5.getController("currentElf");
    tl.setText(Integer.toString(currentElf));
  }

  stroke(204, 102, 0);
  line(540,0,540,750);
  line(1140, 0, 1140, 750);
  line(1440, 0, 1440, 750);
    
  popMatrix();
      
  //cam.beginHUD();
  cp5.draw();
  //cam.endHUD();
}


