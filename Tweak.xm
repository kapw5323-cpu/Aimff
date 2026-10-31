#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <substrate.h>
#import <mach-o/dyld.h>
#include <vector>
#include <cmath>
#include <dlfcn.h>

typedef void* (*il2cpp_domain_get_t)();
typedef void** (*il2cpp_domain_get_assemblies_t)(void*, size_t*);
typedef void* (*il2cpp_assembly_get_image_t)(void*);
typedef const char* (*il2cpp_image_get_name_t)(void*);
typedef size_t (*il2cpp_image_get_class_count_t)(void*);
typedef void* (*il2cpp_image_get_class_t)(void*, size_t);
typedef const char* (*il2cpp_class_get_name_t)(void*);
typedef void* (*il2cpp_class_get_fields_t)(void*, void**);
typedef const char* (*il2cpp_field_get_name_t)(void*);
typedef int32_t (*il2cpp_field_get_offset_t)(void*);
typedef void* (*il2cpp_class_get_methods_t)(void*, void**);
typedef const char* (*il2cpp_method_get_name_t)(void*);
typedef void* (*il2cpp_method_get_pointer_t)(void*);

il2cpp_domain_get_t fn_domain_get; il2cpp_domain_get_assemblies_t fn_domain_get_assemblies;
il2cpp_assembly_get_image_t fn_assembly_get_image; il2cpp_image_get_name_t fn_image_get_name;
il2cpp_image_get_class_count_t fn_image_get_class_count; il2cpp_image_get_class_t fn_image_get_class;
il2cpp_class_get_name_t fn_class_get_name; il2cpp_class_get_fields_t fn_class_get_fields;
il2cpp_field_get_name_t fn_field_get_name; il2cpp_field_get_offset_t fn_field_get_offset;
il2cpp_class_get_methods_t fn_class_get_methods; il2cpp_method_get_name_t fn_method_get_name;
il2cpp_method_get_pointer_t fn_method_get_pointer;

struct Vec3 { float x, y, z; };
uint64_t off_localPlayer = 0, off_playerList = 0, off_playerPos = 0, off_playerHp = 0, off_transform = 0;
uint64_t off_camYaw = 0, off_camPitch = 0;
bool isHooked = false;
float smooth = 0.35f; // Độ mượt (0.1 là giật, 1.0 là siêu mượt)

template <typename T> bool safe_read(uint64_t addr, T& out) {
    if (!addr) return false;
    vm_size_t size = 0;
    return vm_read_overwrite(mach_task_self(), addr, sizeof(T), (vm_address_t)&out, &size) == KERN_SUCCESS;
}

typedef void (*CameraUpdate_t)(void* self);
CameraUpdate_t orig_CameraUpdate = NULL;

void hook_CameraUpdate(void* self) {
    orig_CameraUpdate(self);
    if (!isHooked) return;

    uint64_t gameMgr = 0;
    if (!safe_read((uint64_t)self + off_localPlayer, gameMgr) || !gameMgr) return;
    
    Vec3 localPos; uint64_t localTrans = 0;
    if (!safe_read(gameMgr + off_transform, localTrans) || !safe_read(localTrans + 0x38, localPos)) return;

    uint64_t listPtr = 0; int32_t listLen = 0; uint64_t itemsPtr = 0;
    if (!safe_read(gameMgr + off_playerList, listPtr) || !safe_read(listPtr + 0x10, listLen) || listLen <= 0 || listLen > 64) return;
    if (!safe_read(listPtr + 0x8, itemsPtr)) return;

    Vec3 bestTarget = {0,0,0}; float minDist = 9999.0f; bool found = false;

    for (int i = 0; i < listLen; i++) {
        uint64_t enemy = 0;
        if (!safe_read(itemsPtr + 0x20 + i * 8, enemy) || !enemy || enemy == gameMgr) continue;
        
        float hp = 0;
        if (!safe_read(enemy + off_playerHp, hp) || hp <= 1.0f) continue;

        uint64_t enemyTrans = 0; Vec3 enemyPos;
        if (!safe_read(enemy + off_transform, enemyTrans) || !safe_read(enemyTrans + 0x38, enemyPos)) continue;

        float dx = enemyPos.x - localPos.x, dy = (enemyPos.y + 1.5f) - localPos.y, dz = enemyPos.z - localPos.z;
        float dist = sqrtf(dx*dx + dy*dy + dz*dz);

        if (dist < minDist) { minDist = dist; bestTarget = enemyPos; found = true; }
    }

    if (found) {
        float dx = bestTarget.x - localPos.x, dy = (bestTarget.y + 1.5f) - localPos.y, dz = bestTarget.z - localPos.z;
        float targetYaw = atan2f(dx, dz) * 57.2958f;
        float targetPitch = atan2f(dy, sqrtf(dx*dx + dz*dz)) * 57.2958f;
        
        float curYaw = 0, curPitch = 0;
        if (safe_read((uint64_t)self + off_camYaw, curYaw) && safe_read((uint64_t)self + off_camPitch, curPitch)) {
            float newYaw = curYaw + (targetYaw - curYaw) * smooth;
            float newPitch = curPitch + (targetPitch - curPitch) * smooth;
            vm_write(mach_task_self(), (uint64_t)self + off_camYaw, (vm_address_t)&newYaw, sizeof(float));
            vm_write(mach_task_self(), (uint64_t)self + off_camPitch, (vm_address_t)&newPitch, sizeof(float));
        }
    }
}

__attribute__((constructor))
static void init() {
    void* handle = dlopen("/var/containers/Bundle/Application/*/FreeFire.app/Frameworks/UnityFramework.framework/UnityFramework", RTLD_LAZY);
    if (!handle) return;
    
    fn_domain_get = (il2cpp_domain_get_t)dlsym(handle, "il2cpp_domain_get");
    fn_domain_get_assemblies = (il2cpp_domain_get_assemblies_t)dlsym(handle, "il2cpp_domain_get_assemblies");
    fn_assembly_get_image = (il2cpp_assembly_get_image_t)dlsym(handle, "il2cpp_assembly_get_image");
    fn_image_get_name = (il2cpp_image_get_name_t)dlsym(handle, "il2cpp_image_get_name");
    fn_image_get_class_count = (il2cpp_image_get_class_count_t)dlsym(handle, "il2cpp_image_get_class_count");
    fn_image_get_class = (il2cpp_image_get_class_t)dlsym(handle, "il2cpp_image_get_class");
    fn_class_get_name = (il2cpp_class_get_name_t)dlsym(handle, "il2cpp_class_get_name");
    fn_class_get_fields = (il2cpp_class_get_fields_t)dlsym(handle, "il2cpp_class_get_fields");
    fn_field_get_name = (il2cpp_field_get_name_t)dlsym(handle, "il2cpp_field_get_name");
    fn_field_get_offset = (il2cpp_field_get_offset_t)dlsym(handle, "il2cpp_field_get_offset");
    fn_class_get_methods = (il2cpp_class_get_methods_t)dlsym(handle, "il2cpp_class_get_methods");
    fn_method_get_name = (il2cpp_method_get_name_t)dlsym(handle, "il2cpp_method_get_name");
    fn_method_get_pointer = (il2cpp_method_get_pointer_t)dlsym(handle, "il2cpp_method_get_pointer");

    size_t asmCount = 0;
    void** assemblies = fn_domain_get_assemblies(fn_domain_get(), &asmCount);
    for (size_t i = 0; i < asmCount; i++) {
        void* image = fn_assembly_get_image(assemblies[i]);
        const char* imgName = fn_image_get_name(image);
        if (imgName && strstr(imgName, "Assembly-CSharp")) {
            size_t classCount = fn_image_get_class_count(image);
            for (size_t j = 0; j < classCount; j++) {
                void* klass = fn_image_get_class(image, j);
                const char* className = fn_class_get_name(klass);
                if (className && strstr(className, "Player")) {
                    void* iter = NULL; void* field;
                    while ((field = fn_class_get_fields(klass, &iter))) {
                        const char* fName = fn_field_get_name(field);
                        int offset = fn_field_get_offset(field);
                        if (strstr(fName, "hp")) off_playerHp = offset;
                        if (strstr(fName, "transform")) off_transform = offset;
                        if (strstr(fName, "list")) off_playerList = offset;
                        if (strstr(fName, "local")) off_localPlayer = offset;
                    }
                }
                if (className && strstr(className, "Camera")) {
                    void* mIter = NULL; void* method;
                    while ((method = fn_class_get_methods(klass, &mIter))) {
                        const char* mName = fn_method_get_name(method);
                        if (mName && (strstr(mName, "LateUpdate") || strstr(mName, "Update"))) {
                            void* mPtr = fn_method_get_pointer(method);
                            if (mPtr && !orig_CameraUpdate) {
                                MSHookFunction(mPtr, (void*)hook_CameraUpdate, (void**)&orig_CameraUpdate);
                                isHooked = true;
                            }
                        }
                    }
                }
            }
        }
    }
}
