//
// Copyright 2024, Colias Group, LLC
//
// SPDX-License-Identifier: BSD-2-Clause
//

#![no_std]
#![no_main]
#![allow(clippy::useless_conversion)]

extern crate alloc;

use core::ptr;

use object::{File, Object};

use sel4_root_task::{root_task, Never};

mod child_vspace;
mod object_allocator;

use child_vspace::create_child_vspace;
use object_allocator::ObjectAllocator;

const CHILD_ELF_CONTENTS: &[u8] = include_bytes!(env!("CHILD_ELF"));

const GRANULE_SIZE: usize = sel4::FrameObjectType::GRANULE.bytes(); // 4096

#[repr(C, align(4096))]
struct PagePlaceHolder(#[allow(dead_code)] [u8; GRANULE_SIZE]);

static mut FILL_PAGE_RESERVATION: PagePlaceHolder = PagePlaceHolder([0; GRANULE_SIZE]);

#[root_task(heap_size = 1024 * 64)]
fn main(bootinfo: &sel4::BootInfoPtr) -> sel4::Result<Never> {
    sel4::debug_println!("In root task");

    let mut object_allocator = ObjectAllocator::new(bootinfo);

    let fill_page_addr = ptr::addr_of!(FILL_PAGE_RESERVATION) as usize;

    get_user_image_frame_slot(bootinfo, fill_page_addr)
        .cap()
        .frame_unmap()
        .unwrap();

    let child_image = File::parse(CHILD_ELF_CONTENTS).unwrap();

    let child_vspace_info = create_child_vspace(
        &mut object_allocator,
        &child_image,
        sel4::init_thread::slot::VSPACE.cap(),
        fill_page_addr,
        sel4::init_thread::slot::ASID_POOL.cap(),
    );

    let inter_task_nfn = object_allocator.allocate_fixed_sized::<sel4::cap_type::Notification>();

    let child_cnode_size_bits = 2;
    let child_cnode =
        object_allocator.allocate_variable_sized::<sel4::cap_type::CNode>(child_cnode_size_bits);

    child_cnode
        .relative_bits_with_depth(1, child_cnode_size_bits)
        .mint(
            &sel4::init_thread::slot::CNODE
                .cap()
                .relative(inter_task_nfn),
            sel4::CapRights::write_only(),
            0,
        )
        .unwrap();

    let child_tcb = object_allocator.allocate_fixed_sized::<sel4::cap_type::Tcb>();

    child_tcb
        .tcb_configure(
            sel4::init_thread::slot::NULL.cptr(),
            child_cnode,
            sel4::CNodeCapData::new(0, sel4::WORD_SIZE - child_cnode_size_bits),
            child_vspace_info.child_vspace,
            child_vspace_info.ipc_buffer_addr as sel4::Word,
            child_vspace_info.ipc_buffer_cap,
        )
        .unwrap();

    child_cnode
        .relative_bits_with_depth(2, child_cnode_size_bits)
        .mint(
            &sel4::init_thread::slot::CNODE.cap().relative(child_tcb),
            sel4::CapRights::all(),
            0,
        )
        .unwrap();

    let mut ctx = sel4::UserContext::default();
    *ctx.pc_mut() = child_image.entry().try_into().unwrap();
    child_tcb.tcb_write_all_registers(true, &mut ctx).unwrap();

    inter_task_nfn.wait();

    sel4::debug_println!("TEST_PASS");

    sel4::init_thread::suspend_self()
}

fn get_user_image_frame_slot(
    bootinfo: &sel4::BootInfo,
    addr: usize,
) -> sel4::init_thread::Slot<sel4::cap_type::Granule> {
    extern "C" {
        static __executable_start: usize;
    }
    let user_image_addr = ptr::addr_of!(__executable_start) as usize;
    bootinfo
        .user_image_frames()
        .index(addr / GRANULE_SIZE - user_image_addr / GRANULE_SIZE)
}
