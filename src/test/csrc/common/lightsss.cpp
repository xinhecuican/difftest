#include "lightsss.h"

ForkShareMemory::ForkShareMemory() {
  if ((key_n = ftok(".", 's') < 0)) {
    perror("Fail to ftok\n");
    FAIT_EXIT
  }
  // FORK_PRINTF("key num:%d\n", key_n);

  if ((shm_id = shmget(key_n, 1024, 0666 | IPC_CREAT))==-1) {
    perror("shmget failed...\n");
    FAIT_EXIT
  }
  // FORK_PRINTF("share memory id:%d\n", shm_id);

  if ((info = (shinfo*)(shmat(shm_id, NULL, 0))) == NULL ) {
    perror("shmat failed...\n");
    FAIT_EXIT
  }

  info->flag      = false;
  info->notgood   = false;
  info->endCycles = 0;
  info->oldest    = 0;
}

ForkShareMemory::~ForkShareMemory() {
  if (shmdt(info) == -1) {
    perror("detach error\n");
  }
  shmctl(shm_id, IPC_RMID, NULL);
}

void ForkShareMemory::shwait() {
  while (true) {
    if (info->flag ) {
      if(info->notgood) break;
      else exit(0);
    }
    else {
      sleep(WAIT_INTERVAL);
    }
  }
}

int LightSSS::do_fork() {
  //kill the oldest blocked checkpoint process
  if (slotCnt == SLOT_SIZE) {
    pid_t temp = pidSlot.back();
    pidSlot.pop_back();
    kill(temp, SIGKILL);
    slotCnt--;
  }
  // fork a new checkpoint process and block it
  if ((pid = fork()) < 0) {
    eprintf("[%d]Error: could not fork process!\n", getpid()) ;
    return FORK_ERROR;
  }
  // the original process
  else if (pid != 0) {
    slotCnt++;
    pidSlot.insert(pidSlot.begin(), pid);
    return FORK_OK;
  }
  // for the fork child
  waitProcess = 1;
  forkshm.shwait();
  //checkpoint process wakes up
  //start wave dumping
  bool is_last = forkshm.info->oldest == getpid();
  return (is_last) ? WAIT_LAST : WAIT_EXIT;
}

int LightSSS::wakeup_child(uint64_t cycles) {
  forkshm.info->endCycles = cycles;
  forkshm.info->oldest = pidSlot.back();
  forkshm.info->notgood = true;
  forkshm.info->flag = true;
  int status = -1;
  waitpid(pidSlot.back(), &status, 0);
  return 0;
}

bool LightSSS::is_child() {
  return waitProcess;
}

int LightSSS::do_clear() {
  FORK_PRINTF("clear processes...\n")
  while(!pidSlot.empty()){
    pid_t temp = pidSlot.back();
    pidSlot.pop_back();
    kill(temp, SIGKILL);
    slotCnt--;
  }
  return 0;
}
