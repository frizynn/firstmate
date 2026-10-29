#include <stdio.h>
#include <termios.h>
#include <unistd.h>
int main(void){struct termios t;tcgetattr(0,&t);cfmakeraw(&t);tcsetattr(0,TCSANOW,&t);
printf("STANDIN-READY\r\n");fflush(stdout);unsigned char b[64];ssize_t n;
while((n=read(0,b,sizeof b))>0){printf("GOT");for(ssize_t i=0;i<n;i++)printf(" %02x",b[i]);printf("\r\n");fflush(stdout);}return 0;}
