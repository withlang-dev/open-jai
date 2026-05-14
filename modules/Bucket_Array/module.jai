#scope_export;

#import "Basic";

Bucket_Locator :: struct {
    index: int;
}

Bucket_Array :: struct($T: Type, $BUCKET_SIZE: int) {
    items: [..] T;
    occupied: [..] bool;
    count: int;
    all_buckets: [..] int;
    unfull_buckets: [..] int;
}

bucket_array_add :: (array: *Bucket_Array($T, $BUCKET_SIZE), value: T) -> Bucket_Locator, *T {
    slot := -1;
    for array.occupied {
        if !it {
            slot = it_index;
            break;
        }
    }

    if slot < 0 {
        slot = array.items.count;
        array_add(*array.items, value);
        array_add(*array.occupied, true);
        if (slot % BUCKET_SIZE) == 0 {
            array_add(*array.all_buckets, slot / BUCKET_SIZE);
            array_add(*array.unfull_buckets, slot / BUCKET_SIZE);
        }
    } else {
        array.items[slot] = value;
        array.occupied[slot] = true;
    }

    array.count += 1;
    return .{slot}, *array.items[slot];
}

bucket_array_find :: (array: *Bucket_Array($T, $BUCKET_SIZE), locator: Bucket_Locator) -> T {
    result: T;
    if locator.index < 0 return result;
    if locator.index >= array.items.count return result;
    if !array.occupied[locator.index] return result;
    return array.items[locator.index];
}

bucket_array_remove :: (array: *Bucket_Array($T, $BUCKET_SIZE), locator: Bucket_Locator) {
    if locator.index < 0 return;
    if locator.index >= array.occupied.count return;
    if !array.occupied[locator.index] return;
    array.occupied[locator.index] = false;
    array.count -= 1;
}

bucket_array_reset :: (array: *Bucket_Array($T, $BUCKET_SIZE)) {
    array_reset(*array.items);
    array_reset(*array.occupied);
    array_reset(*array.all_buckets);
    array_reset(*array.unfull_buckets);
    array.count = 0;
}
