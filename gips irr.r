irr.z=function(cf.z,gips=FALSE) {
  irr.freq=1
  #if("Date"!=class(time(cf.z))) {warning("need Date class for zoo index"); return(NA)}
  if(any(is.na(cf.z))) return(NA)
  if(length(cf.z)<=1) return(NA)
  if(all(cf.z<=0)) return(NA)
  if(all(cf.z>=0)) return(NA)
  if(sum(cf.z)==0) return (0)
  if(!is.zoo(cf.z)) {
    timediff=-1+1:length(cf.z)
  } else {
    timeline=time(cf.z)
    timediff=as.numeric(timeline-timeline[1])
    if ("Date"== class(timeline)) irr.freq=365
  }
  if (sum(cf.z)<0) {
    rangehi=0
    rangelo=-.01
    i=0
    # low range on search for negative IRR is -100%
    while(i<100&(sign(npv.znoadjust(rangehi,cf.z,irr.freq,timediff))==sign(npv.znoadjust(rangelo,cf.z,irr.freq,timediff)))) {
      rangehi=rangelo
      rangelo=rangelo-.01
      i=i+1
    }} else {
      rangehi=.01
      rangelo=0
      i=0
      # while hi range on search for positive IRR is 100,000%
      while(i<100000&(sign(npv.znoadjust(rangehi,cf.z,irr.freq,timediff))==sign(npv.znoadjust(rangelo,cf.z,irr.freq,timediff)))) {
        rangelo=rangehi
        rangehi=rangehi+.01
        i=i+1
      }}
  npv1=npv.znoadjust(rangelo,cf.z,irr.freq,timediff)
  npv2=npv.znoadjust(rangehi,cf.z,irr.freq,timediff)
  if (sign(npv1)==sign(npv2)) return(NA)
  cf.n=as.numeric(cf.z)
  #calculate with uniroot if cash flow starts negative and ends positive otherwise do your own search
  if((cf.n[1]<0)&(cf.n[length(cf.n)]>0)) {
    ans=uniroot(npv.znoadjust,c(rangelo,rangehi),cf=cf.z,freq=irr.freq,tdiff=timediff)
    apr=ans$root } else {
      int1=rangelo
      int2=rangehi
      for (i in 1:40) {
        inta=mean(c(int1,int2))
        npva=npv.znoadjust(inta,cf.z,irr.freq,timediff)
        if(sign(npva)==sign(npv1)) {
          int1=inta
          npv1=npva
        } else {
          int2=inta
          npv2=npva
        }}
      apr=mean(int1,int2)  
    }
  # convert IRR to compounding at irr.freq interval
  ans=((1+(apr/irr.freq))^irr.freq)-1
  # convert IRR to GIPS compliant if requested
  if (gips) {
    if(cf.z[1]==0)  cf.z=cf.z[-1]
    dur=index(cf.z)[length(cf.z)]-index(cf.z)[1]
    if(dur<irr.freq) ans=(1+ans)^((as.numeric(dur))/irr.freq)-1
  }
  return (ans)
}
npv.znoadjust=function(i,cf.z,freq,tdiff) {
  d=(1+(i/freq))^tdiff
  sum(cf.z/d)
}
