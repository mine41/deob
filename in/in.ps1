function Double {
    process {
        $_ * 2
    }
}

1,2,3 | Double