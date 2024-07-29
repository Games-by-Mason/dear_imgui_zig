// THIS FILE HAS BEEN AUTO-GENERATED BY THE 'DEAR BINDINGS' GENERATOR.
// **DO NOT EDIT DIRECTLY**
// https://github.com/dearimgui/dear_bindings

#include "imgui.h"
#include "imgui_impl_vulkan.h"

#include <stdio.h>

// Wrap this in a namespace to keep it separate from the C++ API
namespace cimgui
{
#include "cimgui_impl_vulkan.h"
}

// By-value struct conversions

// Function stubs

#ifndef IMGUI_DISABLE

CIMGUI_IMPL_API bool cimgui::cImGui_ImplVulkan_Init(cimgui::ImGui_ImplVulkan_InitInfo* info)
{
    return ::ImGui_ImplVulkan_Init(reinterpret_cast<::ImGui_ImplVulkan_InitInfo*>(info));
}

CIMGUI_IMPL_API void cimgui::cImGui_ImplVulkan_Shutdown(void)
{
    ::ImGui_ImplVulkan_Shutdown();
}

CIMGUI_IMPL_API void cimgui::cImGui_ImplVulkan_NewFrame(void)
{
    ::ImGui_ImplVulkan_NewFrame();
}

CIMGUI_IMPL_API void cimgui::cImGui_ImplVulkan_RenderDrawData(cimgui::ImDrawData* draw_data, VkCommandBuffer command_buffer)
{
    ::ImGui_ImplVulkan_RenderDrawData(reinterpret_cast<::ImDrawData*>(draw_data), command_buffer);
}

CIMGUI_IMPL_API void cimgui::cImGui_ImplVulkan_RenderDrawDataEx(cimgui::ImDrawData* draw_data, VkCommandBuffer command_buffer, VkPipeline pipeline)
{
    ::ImGui_ImplVulkan_RenderDrawData(reinterpret_cast<::ImDrawData*>(draw_data), command_buffer, pipeline);
}

CIMGUI_IMPL_API bool cimgui::cImGui_ImplVulkan_CreateFontsTexture(void)
{
    return ::ImGui_ImplVulkan_CreateFontsTexture();
}

CIMGUI_IMPL_API void cimgui::cImGui_ImplVulkan_DestroyFontsTexture(void)
{
    ::ImGui_ImplVulkan_DestroyFontsTexture();
}

CIMGUI_IMPL_API void cimgui::cImGui_ImplVulkan_SetMinImageCount(uint32_t min_image_count)
{
    ::ImGui_ImplVulkan_SetMinImageCount(min_image_count);
}

CIMGUI_IMPL_API VkDescriptorSet cimgui::cImGui_ImplVulkan_AddTexture(VkSampler sampler, VkImageView image_view, VkImageLayout image_layout)
{
    return ::ImGui_ImplVulkan_AddTexture(sampler, image_view, image_layout);
}

CIMGUI_IMPL_API void       cimgui::cImGui_ImplVulkan_RemoveTexture(VkDescriptorSet descriptor_set)
{
    ::ImGui_ImplVulkan_RemoveTexture(descriptor_set);
}

CIMGUI_IMPL_API bool cimgui::cImGui_ImplVulkan_LoadFunctions(PFN_vkVoidFunction (*loader_func)(const char* function_name, void* user_data))
{
    return ::ImGui_ImplVulkan_LoadFunctions(loader_func);
}

CIMGUI_IMPL_API bool cimgui::cImGui_ImplVulkan_LoadFunctionsEx(PFN_vkVoidFunction (*loader_func)(const char* function_name, void* user_data), void* user_data)
{
    return ::ImGui_ImplVulkan_LoadFunctions(loader_func, user_data);
}

CIMGUI_IMPL_API void          cimgui::cImGui_ImplVulkanH_CreateOrResizeWindow(VkInstance instance, VkPhysicalDevice physical_device, VkDevice device, cimgui::ImGui_ImplVulkanH_Window* wd, uint32_t queue_family, const VkAllocationCallbacks* allocator, int w, int h, uint32_t min_image_count)
{
    ::ImGui_ImplVulkanH_CreateOrResizeWindow(instance, physical_device, device, reinterpret_cast<::ImGui_ImplVulkanH_Window*>(wd), queue_family, allocator, w, h, min_image_count);
}

CIMGUI_IMPL_API void          cimgui::cImGui_ImplVulkanH_DestroyWindow(VkInstance instance, VkDevice device, cimgui::ImGui_ImplVulkanH_Window* wd, const VkAllocationCallbacks* allocator)
{
    ::ImGui_ImplVulkanH_DestroyWindow(instance, device, reinterpret_cast<::ImGui_ImplVulkanH_Window*>(wd), allocator);
}

CIMGUI_IMPL_API VkSurfaceFormatKHR cimgui::cImGui_ImplVulkanH_SelectSurfaceFormat(VkPhysicalDevice physical_device, VkSurfaceKHR surface, const VkFormat* request_formats, int request_formats_count, VkColorSpaceKHR request_color_space)
{
    return ::ImGui_ImplVulkanH_SelectSurfaceFormat(physical_device, surface, request_formats, request_formats_count, request_color_space);
}

CIMGUI_IMPL_API VkPresentModeKHR cimgui::cImGui_ImplVulkanH_SelectPresentMode(VkPhysicalDevice physical_device, VkSurfaceKHR surface, const VkPresentModeKHR* request_modes, int request_modes_count)
{
    return ::ImGui_ImplVulkanH_SelectPresentMode(physical_device, surface, request_modes, request_modes_count);
}

CIMGUI_IMPL_API int           cimgui::cImGui_ImplVulkanH_GetMinImageCountFromPresentMode(VkPresentModeKHR present_mode)
{
    return ::ImGui_ImplVulkanH_GetMinImageCountFromPresentMode(present_mode);
}

#endif // #ifndef IMGUI_DISABLE
