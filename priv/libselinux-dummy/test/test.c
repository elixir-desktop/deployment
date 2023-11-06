#include <selinux.h>
#include <stdio.h>

int main(){
  printf("%d\n",security_getenforce());
}
