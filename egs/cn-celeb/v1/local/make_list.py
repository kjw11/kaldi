import os
import sys

def writefile(filelist,filename):
    fp = open(filename, 'w')
    for line in filelist:
        fp.write(line)
    fp.close()
	
def listFiles(dirpath, suffix): 
    listlines = []
    files = os.listdir(dirpath)
    for eachfile in files:
        curfile = dirpath + os.sep + eachfile
        if os.path.isdir(curfile):
            for mid in listFiles(curfile, suffix):
                listlines.append(mid)
        elif eachfile.endswith(suffix):
            listlines.append([dirpath, eachfile])					   
    return listlines

if __name__ =="__main__":
    if len(sys.argv) != 3:
        sys.stderr.write('\
        Usage: ./make_list.py data scp \
        \n')
    else:
        fin = sys.argv[1]
        fout = sys.argv[2]
        wavscp = []
        utt2spk = []
        list_ = listFiles(fin, 'wav')
        for item in list_:
            utt_id = '-'.join(item[1].split('.')[0].split('_'))
            wavscp.append(utt_id + ' ' + item[0] + os.sep + item[1] + '\n')
            utt2spk.append(utt_id + ' ' + utt_id.split('-')[0] + '\n')
        writefile(wavscp, fout + os.sep + 'wav.scp')
        writefile(utt2spk, fout + os.sep + 'utt2spk')
