---
title: "Calculating IRRs"
author: "Karl Polen"
output: 
  html_document:
    keep_md: TRUE
---



The IRR is a financial metric that presents a variety of problems in practical implementation.  This post explores some issues and solutions.

The IRR is a discount rate that causes the net present value of a cash flow to be zero.  The formula for the NPV is

$NPV=c_0+c_1x^1+c_2x^2+. . .+c_nx^n$

where $c_{0..n}$ represents the cash flows and $x$ is $\frac{1}{1+r}$ and $r$ is the discount rate you are looking for.

So, the IRR is the root of this polynomial.  If the cash flow involves a single initial payment (a negative value in the $c_0$ position) and one or more positive cash flows after that, there is a unique root to the polynomial. If the cash flows follow a more complex pattern, then there will be multiple roots, one for each change in sign in the cash flow.

There are many contexts, for example in private equity and real estate partnerships, where legal documents require the calculation of IRRs.  For example, an investment manager might receive enhanced compensation in the form of an increased share of profits above a certain IRR.  Or investors in a private placement of equity shares might be compelled in a registration rights agreement to sell a portion of their shares in an IPO, provided that a threshold IRR has been met.

The problem is which IRR to use if there is more than one.  Well crafted legal documents will address this and require that if there is a net profit (the sum of the undiscounted cash flows is greater than zero), the lowest positive IRR is used as the IRR.  In the case of a loss, the largest negative IRR (the one closest to zero) is used.  Generally such contracts require using daily cash flows for these calculations.

R provides help in finding the roots of polynomials with the `uniroot` and `polyroot` functions.  `uniroot` requires you to define a function in `x` and it will look for a solution within a range you provide.  `polyroot` directly takes the coefficients of a polynomial as its argument and finds all the real and complex valued roots of the polynomial.  I've experimented with both in practical contexts involving daily cash flows with hundreds of entries over several years and have found neither `uniroot` nor `polyroot` to be a good candidate without modification.  The problem I had with `polyroot` is that you have to provide the coefficients for all the time periods as a 'regular' time series.  `polyroot` works great with monthly or quarterly cash flows which might be OK if you are creating a forecast model.  But if you are using daily cash flows for actual performance or contract compliance measurement you end up with a polynomial with hundreds or even thousands of coefficients.  My experience is that `polyroot` often blows up in that context returning returning a " `root finding code failed` " error message.

`uniroot` works better in that you write a NPV function and it solves for a discount rate that produces a zero NPV.  You only need to deal with the non-zero coefficients and it doesn't have a problem dealing with cash flows with a large number of daily entries over a number of years.  The problem is that it only looks inside a range that you provide, and how do you know where to set the range?  In a modeling environment, you are almost always modeling securities or projects that have a return somewhere in the 0 to 30% range, but cash flows from actual experience range everywhere from -100% to very high positive rates.  You can't set the range this large, because you are at risk at finding values that aren't the ones you want (i.e. the smallest postive IRR for profitable projects and the largest negative IRR for losing projects).

`uniroot` has another problem that you have to deal with for a robust IRR calculation function.  A typical investment analysis project involves a cash flow that starts with a negative value and ends with a positive one.  But there are real world examples of profitable projects that can start with a positive cash flow and end with a negative one.  For example, a project can end with a negative cash flow if you sell the project and then in a later period have some final expenses related to adminstrative, tax or other liability situations.  `uniroot` fails in these calculations where the beginning and ending coefficients have the same sign.

I've written code to deal with all of this.  Here is the basic design:
* Test if the sum of the cash flow is positive or negative
* Search for consecutive values of $r$ in 1% intervals
* Search up from zero if the sum is positive and down if it is negative
* stop when you find an interval where the sign of $NPV$ calculated with $r_i$ and $r_{i+1}$ is different
* Now test to confirm that the values of the cash flow have opposite signs for the initial and final value
* If the last test is confirmed use `uniroot` to find the IRR within the interval found above
* otherwise search for the IRR using a binary search

This approach is, of course, not mathematically rigorous but adequate for contract compliance purposes as long as the contract states a target IRR in whole percent amounts and the purpose of the calculation is to determine if you are above or below a particular hurdle.

The function is called `irr.z` and accepts a `zoo` object of daily cash flows as its argument.  Here is an example of its use.


```r
require(zoo)
require(lubridate)
testcf<- zoo(c(-1,rep(.1/12,119),(1+(.1/12))),as.Date('2014-1-1')+months(0:119))
head(testcf)
```

```
##   2014-01-01   2014-02-01   2014-03-01   2014-04-01   2014-05-01 
## -1.000000000  0.008333333  0.008333333  0.008333333  0.008333333 
##   2014-06-01 
##  0.008333333
```

```r
tail(testcf)
```

```
##  2023-07-01  2023-08-01  2023-09-01  2023-10-01  2023-11-01  2023-12-01 
## 0.008333333 0.008333333 0.008333333 0.008333333 0.008333333 0.008333333
```

```r
irr.z(testcf)
```

```
## [1] -0.001684584
```

Another issue that arises with IRR calculations is rules related to reporting investment performance results.  Most institutional investment managers are required to report under a set of rules known as the Global Investment Performance Standards ("GIPS").  These rules are promulgated and adopted with the goal of ensuring consistency in reporting investment outcomes.  GIPS provides a rule that IRRs for investments lasting less than a year should not be "annualized".  

Let's say you make an investment and sell it for a 10% profit one month later.  The conventional way of calculating the return would be $-1+1.1^{12}$ , or 214 % (assuming 30 day months and 360 days in a year). Under GIPS, you are required to report this project as having an IRR of 10%.  

Here is an illustration of how to use the function to calculate GIPS compliant IRRs.

```r
testcf2<- zoo(c(-1,1.1),as.Date(c("2014-1-1","2014-2-1")))
irr.z(testcf2)
```

```
## [1] 2.071609
```

```r
irr.z(testcf2,gips=TRUE)
```

```
## [1] 0.1000001
```

The formula for calculating the GIPS IRR is:

$irr^{\frac{days}{365}}$

where $irr$ refers to an IRR calculated the regular way and $days$ refers to the days elapsed from the beginning to the end of the investment.


Here is the code for the functions discussed above.  

```r
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
```
