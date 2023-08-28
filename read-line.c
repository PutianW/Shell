/*
 * CS252: Systems Programming
 * Purdue University
 * Example that shows how to read one line with simple editing
 * using raw terminal.
 */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define MAX_BUFFER_LINE 2048

extern void tty_raw_mode(void);

// Buffer where line is stored
int line_length;
char line_buffer[MAX_BUFFER_LINE];

// Simple history array
// This history does not change. 
// Yours have to be updated.
int history_num = 0;
int history_index = 0;
char history[100][MAX_BUFFER_LINE];


char backwards[3] = {27, 91, 68};
char forwards[3] = {27, 91, 67};


int cursor;
char leftover[MAX_BUFFER_LINE];


// move left = 0, move right = 1
// left/right arrow = 0, move = 1
void update_Cursor_and_Leftover(int isLeft, int isArrow) {
  if (isLeft == 0) {
    if (cursor - 1 >= 0) {
      cursor--;
      for (int i = 0; i < line_length - cursor; i++) {
        leftover[i] = line_buffer[i + cursor];
      }
      if (isArrow == 0) {
        write(1, &backwards, 3);
      }
    }
  } else {
    if (cursor + 1 <= line_length) {
      cursor++;
      for (int i = 0; i < line_length - cursor; i++) {
        leftover[i] = line_buffer[i + cursor];
      }
      if (isArrow == 0) {
        write(1, &forwards, 3);
      }
    }
  }
}


// insert = 0, delete = 1
// isDelete = 0, backspace = 1
void update_Buf_and_Std(int isInsert, char c, int isDelete) {
  if (isInsert == 0) {
    line_length++;
    line_buffer[cursor] = c;
    for (int i = cursor + 1; i < line_length; i++) {
      line_buffer[i] = leftover[i - cursor - 1];
      write(1, &line_buffer[i], 1);
    }

    update_Cursor_and_Leftover(1, 1);

    for (int i = line_length - 1; i >= cursor; i--) {
      write(1, &backwards, 3);
    }
  } else {

    if (isDelete == 0) {
      update_Cursor_and_Leftover(1, 0);
    }

    if (cursor > 0) {

      line_length--;

      write(1, &backwards, 3);

      for (int i = cursor - 1; i < line_length; i++) {
        line_buffer[i] = leftover[i - cursor + 1];
        write(1, &line_buffer[i], 1);
      }

      char cha = ' ';
      write(1, &cha, 1);

      update_Cursor_and_Leftover(0, 1);

      for (int i = line_length; i >= cursor; i--) {
        write(1, &backwards, 3);
      }
    }
  }
}



/* 
 * Input a line with some basic editing.
 */
char * read_line() {

  // Set terminal in raw mode
  tty_raw_mode();

  line_length = 0;
  cursor = 0;

  // Read one line until enter is typed
  while (1) {

    // Read one character in raw mode.
    char ch;
    read(0, &ch, 1);

    if (ch >= 32 && ch <= 126) {
      // It is a printable character. 

      // Do echo
      write(1, &ch, 1);

      // If max number of character reached return.
      if (line_length == MAX_BUFFER_LINE - 2) {
        break;
      }

      update_Buf_and_Std(0, ch, 0);

    } else if (ch == 10) {
      // <Enter> was typed. Return line
      
      // Print newline
      write(1, &ch, 1);
      break;

    } else if (ch == 8 || ch == 127) {
      // <backspace> was typed. Remove previous character read.

      update_Buf_and_Std(1, ' ', 1);

    } else if (ch == 4) {
      // <ctrl-H> was typed. Remove the character at cursor.

      update_Buf_and_Std(1, ' ', 0);

    } else if (ch == 5) {
      // <ctrl-E> was typed. Cursor moves to the end.
      
      for (int i = cursor; i <= line_length; i++) {
        update_Cursor_and_Leftover(1, 0);
      }

    } else if (ch == 1) {
      // <ctrl-A> was typed. Cursor moves to the start.

      for (int i = cursor; i > 0; i--) {
        update_Cursor_and_Leftover(0, 0);
      }

    } else if (ch == 27) {
      // Escape sequence. Read two chars more
      //
      // HINT: Use the program "keyboard-example" to
      // see the ascii code for the different chars typed.
      //
      char ch1; 
      char ch2;
      read(0, &ch1, 1);
      read(0, &ch2, 1);
      if (ch1 == 91 && ch2 == 68) {
        // Left arrow.
        
        update_Cursor_and_Leftover(0, 0);

      } else if (ch1 == 91 && ch2 == 67) {
        // Right arrow.

        update_Cursor_and_Leftover(1, 0);

      } else if (ch1 == 91 && ch2 == 66) {
        // Down arrow.

        if (history_num == 0) {
          continue;
        }

        // Erase old line
	      // Print backspaces
	      int i = 0;
	      for (i = cursor; i > 0; i--) {
	        ch = 8;
	        write(1,&ch,1);
	      }

	      // Print spaces on top
	      for (i = 0; i < line_length; i++) {
	        ch = ' ';
	        write(1, &ch, 1);
	      }

	      // Print backspaces
	      for (i = 0; i < line_length; i++) {
	        ch = 8;
	        write(1, &ch, 1);
	      }

	      // Copy line from history
        if (history_index + 1 >= history_num) {
	        history_index = 0;
        } else {
          history_index++;
        }
	      strcpy(line_buffer, history[history_index]);
	      line_length = strlen(line_buffer) - 1;

	      // echo line
	      write(1, line_buffer, line_length);

        cursor = line_length;

      } else if (ch1 == 91 && ch2 == 65) {
	      // Up arrow. Print next line in history.

        if (history_num == 0) {
          continue;
        }

	      // Erase old line
	      // Print backspaces
	      int i = 0;
	      for (i = cursor; i > 0; i--) {
	        ch = 8;
	        write(1,&ch,1);
	      }

	      // Print spaces on top
	      for (i = 0; i < line_length; i++) {
	        ch = ' ';
	        write(1, &ch, 1);
	      }

	      // Print backspaces
	      for (i = 0; i < line_length; i++) {
	        ch = 8;
	        write(1, &ch, 1);
	      }

        if (history_index - 1 < 0) {
	        history_index = history_num - 1;
        } else {
          history_index--;
        }
	      // Copy line from history
	      strcpy(line_buffer, history[history_index]);
	      line_length = strlen(line_buffer) - 1;

	      // echo line
	      write(1, line_buffer, line_length);

        cursor = line_length;

      }
      
    }

  }

  // Add EOL and null char at the end of string
  line_buffer[line_length] = 10;
  line_length++;
  line_buffer[line_length] = 0;

  if (line_length > 1) {
    strcpy(history[history_num], line_buffer);
    history_num++;
    history_index = history_num;
  }

  return line_buffer;
}

