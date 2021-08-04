unsigned long int
fib(unsigned long int n)
{
	if (n <= 1) return n;
	return fib(n - 1) + fib(n - 2);
}

int
main(int argc, char **argv)
{
	unsigned long n = 0, r;
	//	unsigned long long st = get_time(), en;
	r = fib(10);
	//	en = get_time();

	//	print_time(st, en);
	return 0;
}
