/******************************************************************************
 *  Copyright (C) 2011 Michael D. Lowis 
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *****************************************************************************/
 #ifndef PHASES_H
 #define PHASES_H

#include "common.h"
#include "linked_list.h"
#include "ast.h"

void Phases_Compile(String filename);
Node_T* Phases_Parse(String filename);
void Phases_Translate(Node_T* ast);
void Phase_Optimize(void);
void Phases_Assemble(void);
void Phases_Link(void);

 #endif
