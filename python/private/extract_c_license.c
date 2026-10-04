/* Copy the opening C comment, including its delimiters, from a source file. */
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s INPUT OUTPUT\n", argv[0]);
        return 2;
    }
    FILE *input = fopen(argv[1], "rb");
    if (input == NULL) {
        perror(argv[1]);
        return 1;
    }
    FILE *output = fopen(argv[2], "wb");
    if (output == NULL) {
        perror(argv[2]);
        fclose(input);
        return 1;
    }
    int first = fgetc(input);
    int second = fgetc(input);
    if (first != '/' || second != '*') {
        fprintf(stderr, "%s does not start with a C comment\n", argv[1]);
        fclose(input);
        fclose(output);
        return 1;
    }
    if (fputc(first, output) == EOF || fputc(second, output) == EOF) {
        perror(argv[2]);
        fclose(input);
        fclose(output);
        return 1;
    }
    int previous = second;
    int current;
    int found_end = 0;
    while ((current = fgetc(input)) != EOF) {
        if (fputc(current, output) == EOF) {
            perror(argv[2]);
            fclose(input);
            fclose(output);
            return 1;
        }
        if (previous == '*' && current == '/') {
            found_end = 1;
            break;
        }
        previous = current;
    }
    if (!found_end || ferror(input) || fputc('\n', output) == EOF) {
        fprintf(stderr, "cannot extract complete comment from %s\n", argv[1]);
        fclose(input);
        fclose(output);
        return 1;
    }
    int input_close_result = fclose(input);
    int output_close_result = fclose(output);
    if (input_close_result != 0 || output_close_result != 0) {
        perror("closing license file");
        return 1;
    }
    return 0;
}
