import os
import json
import os.path, time
class Song:
    
    def __init__(self, fileLocation, playlist, systemSettings, autoWriteData = False):
        
        self.autoWriteData = autoWriteData
        self.songData = {}
        self.newData = False
        self.cwd = os.getcwd()
        self.playlist = playlist
        self.systemInter = systemSettings

        if os.path.exists(os.getcwd() + "/playlists/" + playlist + "/" + fileLocation + ".json"):
            with open(os.getcwd() + "/playlists/" + playlist + "/" + fileLocation + ".json") as f:
                self.songData = json.load(f)
        else:
            self.songData['title'],self.songData["date"],self.songData["time"], self.songData["length"],self.songData["bpm"],self.songData["userBPM"], self.songData["location"],self.songData["stars"],self.songData["playing"], self.songData["disk"] = self.getMidiInfo(fileLocation)
            self.newData = True
            if self.autoWriteData:
                self.writeData()

    def getTitle(self):
        return self.songData["title"]

    def setTitle(self, title):
        self.songData["title"] = title
        if self.autoWriteData:
            self.writeData()

    def getDate(self):
        return self.songData["date"]

    def setDate(self, date):
        self.songData["date"] = date
        self.newData = True
        if self.autoWriteData:
            self.writeData()

    def getTime(self):
        return self.songData["time"]

    def getLength(self):
        return self.songData["length"]

    def getBPM(self):
        return self.songData["bpm"]

    def getUserBPM(self):
        return self.songData["userBPM"]

    def setUserBPM(self, BPM):
        self.songData["userBPM"] = BPM
        self.newData = True
        if self.autoWriteData:
            self.writeData()

    def getLocation(self):
        return self.songData["location"]

    def getStars(self):
        return str(self.songData["stars"])

    def setStars(self, stars):
        if stars < 0 or stars > 5:
            print("ERROR! NOT IN BOUNDS.")
            return
        self.songData["stars"] = int(stars)
        if self.autoWriteData:
            self.writeData()
        self.newData = True

    def getPlaying(self):
        return self.songData["playing"]

    def setPlaying(self, playing):
        self.songData["playing"] = playing
        self.newData = True

    def getNewData(self):
        return self.songData["newData"]

    def setNewData(self, newData):
        self.newData = newData

    
    def getMidiInfo(self, fileLocation):
        file = self.cwd + '/playlists/' + self.playlist + "/" + fileLocation
        
        midiFile = mido.MidiFile(file)
        mid = []
        midiinfo = Commands().runCommand([self.cwd + '/metamidi/metamidi', '-l' , file])
        midiinfo = midiinfo.split(';')
        LastModifiedTime = self.parseDate(file)
        try:
            return fileLocation, LastModifiedTime, "6:15 pm", midiFile.length, int(midiinfo[6].split(',')[0].split('.')[0]), int(midiinfo[6].split(',')[0].split('.')[0]), fileLocation, "4",0,"1"
        except:
            print("DSFAASDDDDDDDDDDDDDDDDDDDDDDD")

    def parseDate(self,fileLocation):
        temp = time.ctime(os.path.getmtime(fileLocation))
        temp = temp.split()
        if(temp[1] == "Jan"):
            temp[1] = "01"
        if(temp[1] == "Feb"):
            temp[1] = "02"
        if(temp[1] == "Mar"):
            temp[1] = "03"
        if(temp[1] == "Apr"):
            temp[1] = "04"
        if(temp[1] == "May"):
            temp[1] = "05"
        if(temp[1] == "Jun"):
            temp[1] = "06"
        if(temp[1] == "Jul"):
            temp[1] = "07"
        if(temp[1] == "Aug"):
            temp[1] = "08"
        if(temp[1] == "Sep"):
            temp[1] = "09"
        if(temp[1] == "Oct"):
            temp[1] = "10"
        if(temp[1] == "Nov"):
            temp[1] = "11"
        if(temp[1] == "Dec"):
            temp[1] = "12"
        
        return(temp[4] + "-"+ str(temp[1])+ "-" +temp[2])

    def writeData(self):
        with open(os.getcwd() + "/playlists/" + self.playlist + "/" + self.getLocation() + ".json", 'w') as json_file:
            json.dump(self.songData, json_file)

    def getDicot(self):
        return self.songData

    def getList(self):
        return [self.songData['title'],self.songData["date"],self.songData["time"], self.songData["length"],self.songData["bpm"],self.songData["userBPM"], self.songData["location"],self.songData["stars"],self.songData["playing"], self.songData["disk"]]
