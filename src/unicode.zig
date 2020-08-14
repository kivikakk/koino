const ctype = @import("ctype.zig");

// matches anything in the Zs class, plus LF, CR, TAB, FF.
pub fn isWhitespace(uc: u21) bool {
    return uc == 9 or uc == 10 or uc == 12 or uc == 13 or uc == 32 or
        uc == 160 or uc == 5760 or (uc >= 8192 and uc <= 8202) or uc == 8239 or
        uc == 8287 or uc == 12288;
}

// matches anything in the P[cdefios] classes.
pub fn isPunctuation(uc: u21) bool {
    return (uc < 128 and ctype.ispunct(@truncate(u8, uc))) or uc == 161 or uc == 167 or
        uc == 171 or uc == 182 or uc == 183 or uc == 187 or uc == 191 or
        uc == 894 or uc == 903 or (uc >= 1370 and uc <= 1375) or uc == 1417 or
        uc == 1418 or uc == 1470 or uc == 1472 or uc == 1475 or uc == 1478 or
        uc == 1523 or uc == 1524 or uc == 1545 or uc == 1546 or uc == 1548 or
        uc == 1549 or uc == 1563 or uc == 1566 or uc == 1567 or
        (uc >= 1642 and uc <= 1645) or uc == 1748 or (uc >= 1792 and uc <= 1805) or
        (uc >= 2039 and uc <= 2041) or (uc >= 2096 and uc <= 2110) or uc == 2142 or
        uc == 2404 or uc == 2405 or uc == 2416 or uc == 2800 or uc == 3572 or
        uc == 3663 or uc == 3674 or uc == 3675 or (uc >= 3844 and uc <= 3858) or
        uc == 3860 or (uc >= 3898 and uc <= 3901) or uc == 3973 or
        (uc >= 4048 and uc <= 4052) or uc == 4057 or uc == 4058 or
        (uc >= 4170 and uc <= 4175) or uc == 4347 or (uc >= 4960 and uc <= 4968) or
        uc == 5120 or uc == 5741 or uc == 5742 or uc == 5787 or uc == 5788 or
        (uc >= 5867 and uc <= 5869) or uc == 5941 or uc == 5942 or
        (uc >= 6100 and uc <= 6102) or (uc >= 6104 and uc <= 6106) or
        (uc >= 6144 and uc <= 6154) or uc == 6468 or uc == 6469 or uc == 6686 or
        uc == 6687 or (uc >= 6816 and uc <= 6822) or (uc >= 6824 and uc <= 6829) or
        (uc >= 7002 and uc <= 7008) or (uc >= 7164 and uc <= 7167) or
        (uc >= 7227 and uc <= 7231) or uc == 7294 or uc == 7295 or
        (uc >= 7360 and uc <= 7367) or uc == 7379 or (uc >= 8208 and uc <= 8231) or
        (uc >= 8240 and uc <= 8259) or (uc >= 8261 and uc <= 8273) or
        (uc >= 8275 and uc <= 8286) or uc == 8317 or uc == 8318 or uc == 8333 or
        uc == 8334 or (uc >= 8968 and uc <= 8971) or uc == 9001 or uc == 9002 or
        (uc >= 10088 and uc <= 10101) or uc == 10181 or uc == 10182 or
        (uc >= 10214 and uc <= 10223) or (uc >= 10627 and uc <= 10648) or
        (uc >= 10712 and uc <= 10715) or uc == 10748 or uc == 10749 or
        (uc >= 11513 and uc <= 11516) or uc == 11518 or uc == 11519 or
        uc == 11632 or (uc >= 11776 and uc <= 11822) or
        (uc >= 11824 and uc <= 11842) or (uc >= 12289 and uc <= 12291) or
        (uc >= 12296 and uc <= 12305) or (uc >= 12308 and uc <= 12319) or
        uc == 12336 or uc == 12349 or uc == 12448 or uc == 12539 or uc == 42238 or
        uc == 42239 or (uc >= 42509 and uc <= 42511) or uc == 42611 or
        uc == 42622 or (uc >= 42738 and uc <= 42743) or
        (uc >= 43124 and uc <= 43127) or uc == 43214 or uc == 43215 or
        (uc >= 43256 and uc <= 43258) or uc == 43310 or uc == 43311 or
        uc == 43359 or (uc >= 43457 and uc <= 43469) or uc == 43486 or
        uc == 43487 or (uc >= 43612 and uc <= 43615) or uc == 43742 or
        uc == 43743 or uc == 43760 or uc == 43761 or uc == 44011 or uc == 64830 or
        uc == 64831 or (uc >= 65040 and uc <= 65049) or
        (uc >= 65072 and uc <= 65106) or (uc >= 65108 and uc <= 65121) or
        uc == 65123 or uc == 65128 or uc == 65130 or uc == 65131 or
        (uc >= 65281 and uc <= 65283) or (uc >= 65285 and uc <= 65290) or
        (uc >= 65292 and uc <= 65295) or uc == 65306 or uc == 65307 or
        uc == 65311 or uc == 65312 or (uc >= 65339 and uc <= 65341) or
        uc == 65343 or uc == 65371 or uc == 65373 or
        (uc >= 65375 and uc <= 65381) or (uc >= 65792 and uc <= 65794) or
        uc == 66463 or uc == 66512 or uc == 66927 or uc == 67671 or uc == 67871 or
        uc == 67903 or (uc >= 68176 and uc <= 68184) or uc == 68223 or
        (uc >= 68336 and uc <= 68342) or (uc >= 68409 and uc <= 68415) or
        (uc >= 68505 and uc <= 68508) or (uc >= 69703 and uc <= 69709) or
        uc == 69819 or uc == 69820 or (uc >= 69822 and uc <= 69825) or
        (uc >= 69952 and uc <= 69955) or uc == 70004 or uc == 70005 or
        (uc >= 70085 and uc <= 70088) or uc == 70093 or
        (uc >= 70200 and uc <= 70205) or uc == 70854 or
        (uc >= 71105 and uc <= 71113) or (uc >= 71233 and uc <= 71235) or
        (uc >= 74864 and uc <= 74868) or uc == 92782 or uc == 92783 or
        uc == 92917 or (uc >= 92983 and uc <= 92987) or uc == 92996 or
        uc == 113823;
}
